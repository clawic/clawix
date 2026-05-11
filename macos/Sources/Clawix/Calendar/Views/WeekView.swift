import SwiftUI

struct WeekView: View {
    @ObservedObject var manager: CalendarManager
    @State private var now: Date = Date()

    private var calendar: Foundation.Calendar { manager.foundationCalendar }
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            headerStrip
            Rectangle().fill(CalendarTokens.Divider.hairline).frame(height: 1)
            scrollableHours
        }
        .onReceive(timer) { now = $0 }
    }

    private var days: [Date] {
        let start = manager.startOfWeek(for: manager.selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var headerStrip: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CalendarTokens.Geometry.hourGutterWidth)
            ForEach(days, id: \.self) { date in
                let isToday = calendar.isDateInToday(date)
                VStack(spacing: 2) {
                    Text(weekdayShort(date))
                        .font(.system(size: CalendarTokens.TypeSize.weekdayLegend, weight: .medium))
                        .tracking(0.5)
                        .foregroundColor(CalendarTokens.Ink.secondary)
                    ZStack {
                        if isToday {
                            Circle()
                                .fill(CalendarTokens.Accent.todayFill)
                                .frame(width: 26, height: 26)
                        }
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 17, weight: isToday ? .semibold : .regular))
                            .foregroundColor(isToday ? .white : CalendarTokens.Ink.primary)
                    }
                    .frame(height: 26)
                }
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    manager.selectedDate = date
                    manager.setViewMode(.day)
                }
            }
        }
        .padding(.vertical, 8)
        .background(CalendarTokens.Surface.window)
    }

    private func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEE"
        return f.string(from: d).uppercased()
    }

    private var scrollableHours: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    grid
                    eventsLayer
                    nowLine
                }
                .frame(height: 24 * CalendarTokens.Geometry.hourRowHeight)
            }
            .thinScrollers()
            .onAppear {
                proxy.scrollTo(8, anchor: .top)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 0) {
                    Text(hourLabel(hour))
                        .font(.system(size: CalendarTokens.TypeSize.eventTime))
                        .foregroundColor(CalendarTokens.Ink.secondary)
                        .frame(width: CalendarTokens.Geometry.hourGutterWidth - 6, alignment: .trailing)
                        .padding(.trailing, 6)
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { date in
                            ZStack(alignment: .topLeading) {
                                if calendar.isDateInToday(date) {
                                    CalendarTokens.Accent.todayFaint
                                }
                                Color.clear
                            }
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(CalendarTokens.Divider.hairline).frame(width: 1)
                            }
                        }
                    }
                }
                .frame(height: CalendarTokens.Geometry.hourRowHeight)
                .id(hour)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(CalendarTokens.Divider.hairline).frame(height: 1)
                }
            }
        }
    }

    private var eventsLayer: some View {
        GeometryReader { geo in
            let dayWidth = (geo.size.width - CalendarTokens.Geometry.hourGutterWidth) / CGFloat(days.count)
            ZStack(alignment: .topLeading) {
                ForEach(Array(days.enumerated()), id: \.offset) { (idx, date) in
                    ForEach(manager.eventsForDay(date)) { event in
                        let offset = eventOffset(event: event, day: date)
                        let height = max(20, eventHeight(event))
                        EventChip(event: event,
                                   color: manager.color(forCalendarID: event.calendarID),
                                   style: .timedBar)
                            .frame(width: dayWidth - 4, height: height, alignment: .topLeading)
                            .offset(x: CalendarTokens.Geometry.hourGutterWidth + CGFloat(idx) * dayWidth + 2,
                                     y: offset)
                    }
                }
            }
        }
    }

    private var nowLine: some View {
        let day = days.first { calendar.isDate($0, inSameDayAs: now) }
        return GeometryReader { geo in
            if let day, let _ = days.firstIndex(of: day) {
                let dayWidth = (geo.size.width - CalendarTokens.Geometry.hourGutterWidth) / CGFloat(days.count)
                let idx = CGFloat(days.firstIndex(of: day) ?? 0)
                let minutesSinceMidnight = nowMinutesSinceMidnight()
                let offsetY = CGFloat(minutesSinceMidnight) / 60.0 * CalendarTokens.Geometry.hourRowHeight
                ZStack(alignment: .leading) {
                    Circle()
                        .fill(CalendarTokens.Accent.todayFill)
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(CalendarTokens.Accent.todayFill)
                        .frame(height: 1)
                        .padding(.leading, 6)
                }
                .frame(width: dayWidth, alignment: .leading)
                .offset(x: CalendarTokens.Geometry.hourGutterWidth + idx * dayWidth,
                         y: offsetY - 4)
            }
        }
    }

    private func eventOffset(event: CalendarEvent, day: Date) -> CGFloat {
        let dayStart = calendar.startOfDay(for: day)
        let effectiveStart = max(event.startDate, dayStart)
        let minutes = effectiveStart.timeIntervalSince(dayStart) / 60.0
        return CGFloat(minutes) / 60.0 * CalendarTokens.Geometry.hourRowHeight
    }

    private func eventHeight(_ event: CalendarEvent) -> CGFloat {
        let minutes = event.duration / 60.0
        return CGFloat(minutes) / 60.0 * CalendarTokens.Geometry.hourRowHeight
    }

    private func nowMinutesSinceMidnight() -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func hourLabel(_ hour: Int) -> String {
        let usesAMPM = Locale.current.identifier.hasPrefix("en")
        if usesAMPM {
            let h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            let suffix = hour < 12 ? "am" : "pm"
            return "\(h) \(suffix)"
        }
        return String(format: "%02d:00", hour)
    }
}
