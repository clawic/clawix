import Foundation
import SwiftUI

final class DummyCalendarBackend: CalendarBackend, @unchecked Sendable {

    private actor Store {
        var events: [String: CalendarEvent] = [:]
        var seeded = false

        func seed(_ list: [CalendarEvent]) {
            guard !seeded else { return }
            seeded = true
            for ev in list { events[ev.id] = ev }
        }

        func all() -> [CalendarEvent] { Array(events.values) }

        func upsert(_ event: CalendarEvent) { events[event.id] = event }

        func remove(_ id: String) -> Bool {
            events.removeValue(forKey: id) != nil
        }
    }

    private let storage = Store()

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
        await storage.seed(seedEvents())
        let all = await storage.all()
        return all.filter { $0.intersects(start: start, end: end) }
    }

    func save(draft: CalendarEventDraft) async -> CalendarWriteResult {
        let id = draft.id ?? "dummy-\(UUID().uuidString.prefix(8))"
        let ev = CalendarEvent(
            id: id,
            title: draft.title,
            location: draft.location,
            notes: draft.notes,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            sourceID: draft.calendarID == "holidays" ? "subscribed" : "local",
            calendarID: draft.calendarID
        )
        await storage.upsert(ev)
        return .success
    }

    func delete(eventID: String) async -> CalendarWriteResult {
        let removed = await storage.remove(eventID)
        return removed ? .success : .failure("Event not found.")
    }

    private func seedEvents() -> [CalendarEvent] {
        let cal = Foundation.Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let rangeStart = cal.date(byAdding: .day, value: -60, to: today) else { return [] }
        let dayCount = 120
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
            guard let day = cal.date(byAdding: .day, value: offset, to: rangeStart) else { continue }
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
                    sourceID: t.source == "holidays" ? "subscribed" : "local",
                    calendarID: t.source
                ))
            }
            if offset % 14 == 7 {
                let base = cal.startOfDay(for: day)
                if let end = cal.date(byAdding: .day, value: 1, to: base) {
                    samples.append(CalendarEvent(
                        id: "dummy-allday-\(offset)",
                        title: "Holiday",
                        location: nil,
                        notes: nil,
                        startDate: base,
                        endDate: end,
                        isAllDay: true,
                        sourceID: "subscribed",
                        calendarID: "holidays"
                    ))
                }
            }
        }
        return samples
    }
}
