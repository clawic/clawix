import Foundation
import SwiftUI
import EventKit

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
        }
    }
}

@MainActor
final class CalendarManager: ObservableObject {

    enum AccessState: Equatable {
        case unknown
        case requesting
        case granted
        case denied(String)
        case unavailable
    }

    @Published private(set) var access: AccessState = .unknown
    @Published private(set) var sources: [CalendarSource] = []
    @Published private(set) var events: [CalendarEvent] = []
    @Published var hiddenSourceIDs: Set<String> = []
    @Published var viewMode: CalendarViewMode = .month
    @Published var selectedDate: Date = Date()
    @Published var miniMonthAnchor: Date = Date()
    @Published var searchQuery: String = ""

    private let backend: CalendarBackend
    private let calendar: Foundation.Calendar

    init(backend: CalendarBackend? = nil, calendar: Foundation.Calendar = .current) {
        self.backend = backend ?? CalendarManager.makeDefaultBackend()
        var cal = calendar
        cal.firstWeekday = calendar.firstWeekday
        self.calendar = cal
    }

    private static func makeDefaultBackend() -> CalendarBackend {
        let env = ProcessInfo.processInfo.environment
        if env["CLAWIX_DISABLE_BACKEND"] == "1" || env["CLAWIX_DUMMY_MODE"] == "1" {
            return DummyCalendarBackend()
        }
        return EventKitCalendarBackend()
    }

    func bootstrap() async {
        guard access == .unknown else { return }
        access = .requesting
        let result = await backend.requestAccess()
        switch result {
        case .granted:
            access = .granted
            await reload()
        case .denied(let reason):
            access = .denied(reason)
        case .unavailable:
            access = .unavailable
        }
    }

    func reload() async {
        let (start, end) = visibleRange(for: viewMode, anchor: selectedDate)
        let fetchedSources = await backend.loadSources()
        let fetchedEvents = await backend.loadEvents(start: start, end: end)
        self.sources = fetchedSources
        self.events = fetchedEvents
    }

    func setViewMode(_ mode: CalendarViewMode) {
        guard viewMode != mode else { return }
        viewMode = mode
        Task { await reload() }
    }

    func goToToday() {
        selectedDate = Date()
        miniMonthAnchor = Date()
        Task { await reload() }
    }

    func step(forward: Bool) {
        let direction = forward ? 1 : -1
        var components = DateComponents()
        switch viewMode {
        case .day:   components.day   = direction
        case .week:  components.day   = direction * 7
        case .month: components.month = direction
        case .year:  components.year  = direction
        }
        if let next = calendar.date(byAdding: components, to: selectedDate) {
            selectedDate = next
            Task { await reload() }
        }
    }

    func goTo(date: Date) {
        selectedDate = date
        Task { await reload() }
    }

    func stepMiniMonth(forward: Bool) {
        let direction = forward ? 1 : -1
        if let next = calendar.date(byAdding: .month, value: direction, to: miniMonthAnchor) {
            miniMonthAnchor = next
        }
    }

    func toggleSourceVisibility(_ source: CalendarSource) {
        if hiddenSourceIDs.contains(source.id) {
            hiddenSourceIDs.remove(source.id)
        } else {
            hiddenSourceIDs.insert(source.id)
        }
    }

    func isVisible(_ source: CalendarSource) -> Bool {
        !hiddenSourceIDs.contains(source.id)
    }

    var visibleEvents: [CalendarEvent] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return events.filter { event in
            guard !hiddenSourceIDs.contains(event.calendarID) else { return false }
            guard !query.isEmpty else { return true }
            return event.title.lowercased().contains(query)
                || (event.location ?? "").lowercased().contains(query)
                || (event.notes ?? "").lowercased().contains(query)
        }
    }

    func eventsForDay(_ day: Date) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return visibleEvents.filter { $0.intersects(start: start, end: end) }
    }

    func source(forCalendarID id: String) -> CalendarSource? {
        sources.first { $0.id == id }
    }

    func color(forCalendarID id: String) -> Color {
        source(forCalendarID: id)?.color ?? CalendarTokens.Ink.secondary
    }

    func visibleRange(for mode: CalendarViewMode, anchor: Date) -> (Date, Date) {
        switch mode {
        case .day:
            let start = calendar.startOfDay(for: anchor)
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? anchor)
        case .week:
            let weekStart = startOfWeek(for: anchor)
            return (weekStart, calendar.date(byAdding: .day, value: 7, to: weekStart) ?? anchor)
        case .month:
            let monthStart = startOfMonth(for: anchor)
            let next = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? anchor
            let gridStart = startOfWeek(for: monthStart)
            let gridEnd = calendar.date(byAdding: .day, value: 7, to: startOfWeek(for: next)) ?? next
            return (gridStart, gridEnd)
        case .year:
            let yearStart = calendar.date(from: calendar.dateComponents([.year], from: anchor)) ?? anchor
            let next = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? anchor
            return (yearStart, next)
        }
    }

    func startOfWeek(for date: Date) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? date
    }

    func startOfMonth(for date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    var foundationCalendar: Foundation.Calendar { calendar }
}

protocol CalendarBackend: Sendable {
    func requestAccess() async -> CalendarAccessResult
    func loadSources() async -> [CalendarSource]
    func loadEvents(start: Date, end: Date) async -> [CalendarEvent]
}

enum CalendarAccessResult: Equatable {
    case granted
    case denied(String)
    case unavailable
}
