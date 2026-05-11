import SwiftUI

struct DayView: View {
    @ObservedObject var manager: CalendarManager
    @State private var now: Date = Date()
    @State private var dragStartY: CGFloat?
    @State private var dragEndY: CGFloat?

    private var calendar: Foundation.Calendar { manager.foundationCalendar }
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            allDayBand
            Rectangle().fill(CalendarTokens.Divider.hairline).frame(height: 1)
            scrollableHours
        }
        .onReceive(timer) { now = $0 }
    }

    private var titleStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(longDate(manager.selectedDate))
                .font(.system(size: CalendarTokens.TypeSize.title, weight: .semibold))
                .foregroundColor(CalendarTokens.Ink.primary)
            Text(weekdayLong(manager.selectedDate))
                .font(.system(size: CalendarTokens.TypeSize.subtitle))
                .foregroundColor(CalendarTokens.Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(CalendarTokens.Surface.window)
    }

    @ViewBuilder
    private var allDayBand: some View {
        let allDay = manager.allDayEventsForDay(manager.selectedDate)
        if !allDay.isEmpty {
            HStack(spacing: 6) {
                Text("All day")
                    .font(.system(size: 11))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .frame(width: CalendarTokens.Geometry.hourGutterWidth - 6, alignment: .trailing)
                    .padding(.trailing, 6)
                HStack(spacing: 4) {
                    ForEach(allDay) { ev in
                        Button { manager.selectedEventID = ev.id } label: {
                            EventChip(event: ev,
                                       color: manager.color(forCalendarID: ev.calendarID),
                                       style: .compact)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .background(CalendarTokens.Surface.window)
            .overlay(alignment: .bottom) {
                Rectangle().fill(CalendarTokens.Divider.hairline).frame(height: 1)
            }
        }
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
            .onAppear { proxy.scrollTo(8, anchor: .top) }
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
                    Rectangle()
                        .fill(Color.clear)
                        .frame(maxWidth: .infinity)
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
            let contentWidth = geo.size.width - CalendarTokens.Geometry.hourGutterWidth - 16
            ZStack(alignment: .topLeading) {
                ForEach(manager.eventsForDay(manager.selectedDate)) { event in
                    let offset = eventOffset(event: event)
                    let height = max(24, eventHeight(event))
                    DraggableTimedChip(
                        manager: manager,
                        event: event,
                        rowHeight: CalendarTokens.Geometry.hourRowHeight
                    )
                    .frame(width: contentWidth, height: height, alignment: .topLeading)
                    .offset(x: CalendarTokens.Geometry.hourGutterWidth + 8, y: offset)
                }
            }
        }
    }

    @ViewBuilder
    private var ghostLayer: some View {
        if let s = dragStartY, let e = dragEndY {
            GeometryReader { geo in
                let contentWidth = geo.size.width - CalendarTokens.Geometry.hourGutterWidth - 16
                let top = min(s, e)
                let bottom = max(s, e)
                RoundedRectangle(cornerRadius: CalendarTokens.Radius.eventChip, style: .continuous)
                    .fill(CalendarTokens.Accent.todayFill.opacity(0.65))
                    .frame(width: contentWidth, height: max(20, bottom - top))
                    .offset(x: CalendarTokens.Geometry.hourGutterWidth + 8, y: top)
            }
            .allowsHitTesting(false)
        }
    }

    private var nowLine: some View {
        GeometryReader { geo in
            if calendar.isDate(manager.selectedDate, inSameDayAs: now) {
                let minutes = nowMinutesSinceMidnight()
                let offsetY = CGFloat(minutes) / 60.0 * CalendarTokens.Geometry.hourRowHeight
                ZStack(alignment: .leading) {
                    Circle()
                        .fill(CalendarTokens.Accent.todayFill)
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(CalendarTokens.Accent.todayFill)
                        .frame(height: 1)
                        .padding(.leading, 6)
                }
                .frame(width: geo.size.width, alignment: .leading)
                .offset(x: CalendarTokens.Geometry.hourGutterWidth - 4, y: offsetY - 4)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if dragStartY == nil { dragStartY = snap(value.startLocation.y) }
                dragEndY = snap(value.location.y)
            }
            .onEnded { value in
                guard let s = dragStartY, let e = dragEndY else { return }
                let top = min(s, e)
                let bottom = max(s, e)
                let startMinutes = Int(top / CalendarTokens.Geometry.hourRowHeight * 60)
                let endMinutes = max(startMinutes + 15, Int(bottom / CalendarTokens.Geometry.hourRowHeight * 60))
                if let startDate = dateAt(minutes: startMinutes),
                   let endDate = dateAt(minutes: endMinutes) {
                    manager.startCreate(at: startDate, duration: endDate.timeIntervalSince(startDate))
                }
                dragStartY = nil
                dragEndY = nil
            }
    }

    private func snap(_ y: CGFloat) -> CGFloat {
        let perQuarter = CalendarTokens.Geometry.hourRowHeight / 4
        return (y / perQuarter).rounded() * perQuarter
    }

    private func dateAt(minutes: Int) -> Date? {
        let dayStart = calendar.startOfDay(for: manager.selectedDate)
        return calendar.date(byAdding: .minute, value: max(0, min(24 * 60 - 1, minutes)), to: dayStart)
    }

    private func eventOffset(event: CalendarEvent) -> CGFloat {
        let dayStart = calendar.startOfDay(for: manager.selectedDate)
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

    private func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = manager.localeForDisplay
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: d)
    }

    private func weekdayLong(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = manager.localeForDisplay
        f.dateFormat = "EEEE"
        return f.string(from: d).capitalized
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
