import Foundation
import SwiftUI

final class DummyCalendarBackend: CalendarBackend, @unchecked Sendable {

    func requestAccess() async -> CalendarAccessResult { .granted }

    func loadSources() async -> [CalendarSource] {
        [
            CalendarSource(id: "personal", sourceID: "local", title: "Personal",
                           color: .blue, isSubscribed: false, isReadOnly: false),
            CalendarSource(id: "work", sourceID: "local", title: "Work",
                           color: .orange, isSubscribed: false, isReadOnly: false),
            CalendarSource(id: "family", sourceID: "local", title: "Family",
                           color: .green, isSubscribed: false, isReadOnly: false),
            CalendarSource(id: "holidays", sourceID: "subscribed", title: "Holidays",
                           color: .red, isSubscribed: true, isReadOnly: true)
        ]
    }

    func loadEvents(start: Date, end: Date) async -> [CalendarEvent] {
        let cal = Foundation.Calendar.current
        let dayCount = cal.dateComponents([.day], from: start, to: end).day ?? 30
        var samples: [CalendarEvent] = []
        let templates: [(title: String, hour: Int, minute: Int, duration: Int, source: String)] = [
            ("Morning standup",  9, 30, 30,  "work"),
            ("Design review",   11,  0, 60,  "work"),
            ("Lunch with Alex", 13,  0, 75,  "personal"),
            ("Focus block",     15,  0, 90,  "work"),
            ("Pickup kids",     17, 15, 30,  "family"),
            ("Yoga",            19,  0, 60,  "personal")
        ]
        for offset in 0..<dayCount {
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            let weekday = cal.component(.weekday, from: day)
            let isWeekend = (weekday == 1 || weekday == 7)
            let slots = isWeekend ? [templates[2], templates[5]] : templates
            for (idx, t) in slots.enumerated() {
                let base = cal.startOfDay(for: day)
                guard let s = cal.date(byAdding: DateComponents(hour: t.hour, minute: t.minute), to: base),
                      let e = cal.date(byAdding: .minute, value: t.duration, to: s) else { continue }
                samples.append(CalendarEvent(
                    id: "dummy-\(offset)-\(idx)",
                    title: t.title,
                    location: nil,
                    notes: nil,
                    startDate: s,
                    endDate: e,
                    isAllDay: false,
                    sourceID: "local",
                    calendarID: t.source
                ))
            }
        }
        return samples
    }
}
