import Foundation
import SwiftUI
import EventKit

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
    @Published private(set) var hiddenSourceIDs: Set<String> = []
    @Published var visibleRangeStart: Date
    @Published var visibleRangeEnd: Date

    private let backend: CalendarBackend

    init(backend: CalendarBackend? = nil) {
        let resolved = backend ?? CalendarManager.makeDefaultBackend()
        self.backend = resolved
        let now = Date()
        let cal = Foundation.Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let endOfMonth = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? now
        self.visibleRangeStart = cal.startOfDay(for: startOfMonth)
        self.visibleRangeEnd = cal.date(byAdding: DateComponents(day: 1), to: cal.startOfDay(for: endOfMonth)) ?? now
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
        let fetchedSources = await backend.loadSources()
        let fetchedEvents = await backend.loadEvents(start: visibleRangeStart, end: visibleRangeEnd)
        self.sources = fetchedSources
        self.events = fetchedEvents
    }

    func setVisibleRange(start: Date, end: Date) async {
        self.visibleRangeStart = start
        self.visibleRangeEnd = end
        if access == .granted {
            await reload()
        }
    }

    func toggleSource(_ source: CalendarSource) {
        if hiddenSourceIDs.contains(source.id) {
            hiddenSourceIDs.remove(source.id)
        } else {
            hiddenSourceIDs.insert(source.id)
        }
    }

    var filteredEvents: [CalendarEvent] {
        events.filter { !hiddenSourceIDs.contains($0.calendarID) }
    }
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
