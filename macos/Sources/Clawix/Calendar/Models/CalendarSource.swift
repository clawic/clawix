import Foundation
import SwiftUI

struct CalendarSource: Identifiable, Equatable, Hashable {
    let id: String
    let sourceID: String
    var title: String
    var color: Color
    var isSubscribed: Bool
    var isReadOnly: Bool

    static func == (lhs: CalendarSource, rhs: CalendarSource) -> Bool {
        lhs.id == rhs.id
            && lhs.sourceID == rhs.sourceID
            && lhs.title == rhs.title
            && lhs.isSubscribed == rhs.isSubscribed
            && lhs.isReadOnly == rhs.isReadOnly
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct CalendarSourceGroup: Identifiable, Equatable {
    let id: String
    var title: String
    var calendars: [CalendarSource]
}
