import SwiftUI

struct WeekView: View {
    @ObservedObject var manager: CalendarManager
    @State private var now: Date = Date()
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?

    private var calendar: Foundation.Calendar { manager.foundationCalendar }
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            headerStrip
            allDayBand
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

    @ViewBuilder
    private var allDayBand: some View {
        let allDayByDay: [(Date, [CalendarEvent])] = days.map { ($0, manager.allDayEventsForDay($0)) }
        let hasAny = allDayByDay.contains { !$0.1.isEmpty }
        if hasAny {
            HStack(spacing: 0) {
                Text("All day")
                    .font(.system(size: 11))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .frame(width: CalendarTokens.Geometry.hourGutterWidth - 6, alignment: .trailing)
                    .padding(.trailing, 6)
                HStack(spacing: 0) {
                    ForEach(allDayByDay, id: \.0) { (_, list) in
                        VStack(spacing: 2) {
                            ForEach(list) { ev in
                                Button { manager.selectedEventID = ev.id } label: {
                                    EventChip(event: ev,
                                               color: manager.color(forCalendarID: ev.calendarID),
                                               style: .compact)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(CalendarTokens.Surface.window)
            .overlay(alignment: .bottom) {
                Rectangle().fill(CalendarTokens.Divider.hairline).frame(height: 1)
            }
        }
    }

    private func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = manager.localeForDisplay
        f.dateFormat = "EEE"
        return f.string(from: d).uppercased()
    }

    private var scrollableHours: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    grid
                    eventsLayer
                    ghostLayer
                    nowLine
                }
                .frame(height: 24 * CalendarTokens.Geometry.hourRowHeight)
                .contentShape(Rectangle())
                .gesture(dragGesture)
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
                        Button { manager.selectedEventID = event.id } label: {
                            EventChip(event: event,
                                       color: manager.color(forCalendarID: event.calendarID),
                                       style: .timedBar)
                        }
                        .buttonStyle(.plain)
                        .frame(width: dayWidth - 4, height: height, alignment: .topLeading)
                        .offset(x: CalendarTokens.Geometry.hourGutterWidth + CGFloat(idx) * dayWidth + 2,
                                 y: offset)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ghostLayer: some View {
        if let s = dragStart, let e = dragEnd {
            GeometryReader { geo in
                let dayWidth = (geo.size.width - CalendarTokens.Geometry.hourGutterWidth) / CGFloat(days.count)
                let col = columnFor(x: s.x, dayWidth: dayWidth)
                let top = min(s.y, e.y)
                let bottom = max(s.y, e.y)
                RoundedRectangle(cornerRadius: CalendarTokens.Radius.eventChip, style: .continuous)
                    .fill(CalendarTokens.Accent.todayFill.opacity(0.65))
                    .frame(width: dayWidth - 4, height: max(20, bottom - top))
                    .offset(x: CalendarTokens.Geometry.hourGutterWidth + CGFloat(col) * dayWidth + 2,
                             y: top)
            }
            .allowsHitTesting(false)
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil { dragStart = snap(value.startLocation) }
                dragEnd = snap(value.location)
            }
            .onEnded { _ in
                guard let s = dragStart, let e = dragEnd else { return }
                guard s.x > CalendarTokens.Geometry.hourGutterWidth else {
                    dragStart = nil; dragEnd = nil; return
                }
                let top = min(s.y, e.y)
                let bottom = max(s.y, e.y)
                let startMinutes = Int(top / CalendarTokens.Geometry.hourRowHeight * 60)
                let endMinutes = max(startMinutes + 15, Int(bottom / CalendarTokens.Geometry.hourRowHeight * 60))
                let columnIndex = columnFor(x: s.x)
                if columnIndex < days.count,
                   let startDate = dateAt(day: days[columnIndex], minutes: startMinutes),
                   let endDate = dateAt(day: days[columnIndex], minutes: endMinutes) {
                    manager.startCreate(at: startDate, duration: endDate.timeIntervalSince(startDate))
                }
                dragStart = nil
                dragEnd = nil
            }
    }

    private func columnFor(x: CGFloat, dayWidth: CGFloat? = nil) -> Int {
        let w = dayWidth ?? max(40, (NSScreen.main?.frame.width ?? 1440) / CGFloat(days.count))
        let relX = x - CalendarTokens.Geometry.hourGutterWidth
        return max(0, min(days.count - 1, Int(relX / w)))
    }

    private func snap(_ p: CGPoint) -> CGPoint {
        let perQuarter = CalendarTokens.Geometry.hourRowHeight / 4
        return CGPoint(x: p.x, y: (p.y / perQuarter).rounded() * perQuarter)
    }

    private func dateAt(day: Date, minutes: Int) -> Date? {
        let base = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: max(0, min(24 * 60 - 1, minutes)), to: base)
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
        let usesAMPM = manager.localeForDisplay.identifier.hasPrefix("en")
        if usesAMPM {
            let h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            let suffix = hour < 12 ? "am" : "pm"
            return "\(h) \(suffix)"
        }
        return String(format: "%02d:00", hour)
    }
}
