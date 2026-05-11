import SwiftUI

struct DayView: View {
    @ObservedObject var manager: CalendarManager
    @State private var now: Date = Date()

    private var calendar: Foundation.Calendar { manager.foundationCalendar }
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
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
                    EventChip(event: event,
                               color: manager.color(forCalendarID: event.calendarID),
                               style: .timedBar)
                        .frame(width: contentWidth, height: height, alignment: .topLeading)
                        .offset(x: CalendarTokens.Geometry.hourGutterWidth + 8, y: offset)
                }
            }
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
        f.locale = Locale.current
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: d)
    }

    private func weekdayLong(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEEE"
        return f.string(from: d).capitalized
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
