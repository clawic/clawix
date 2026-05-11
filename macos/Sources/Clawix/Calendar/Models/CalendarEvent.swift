import Foundation
import SwiftUI

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    var title: String
    var location: String?
    var notes: String?
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var sourceID: String
    var calendarID: String

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.location == rhs.location
            && lhs.notes == rhs.notes
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.isAllDay == rhs.isAllDay
            && lhs.sourceID == rhs.sourceID
            && lhs.calendarID == rhs.calendarID
    }
}

extension CalendarEvent {
    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    func intersects(start: Date, end: Date) -> Bool {
        startDate < end && endDate > start
    }
}
