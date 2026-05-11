import Foundation
import SwiftUI
import EventKit
import AppKit

final class EventKitCalendarBackend: CalendarBackend, @unchecked Sendable {

    private let store = EKEventStore()

    func requestAccess() async -> CalendarAccessResult {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            return .granted
        case .denied:
            return .denied("Calendar access denied in System Settings.")
        case .restricted:
            return .denied("Calendar access is restricted on this device.")
        case .writeOnly:
            return .granted
        case .notDetermined:
            do {
                if #available(macOS 14.0, *) {
                    let granted = try await store.requestFullAccessToEvents()
                    return granted ? .granted : .denied("Permission not granted.")
                } else {
                    let granted: Bool = await withCheckedContinuation { cont in
                        store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
                    }
                    return granted ? .granted : .denied("Permission not granted.")
                }
            } catch {
                return .denied(error.localizedDescription)
            }
        @unknown default:
            return .unavailable
        }
    }

    func loadSources() async -> [CalendarSource] {
        let calendars = store.calendars(for: .event)
        return calendars.map { cal in
            CalendarSource(
                id: cal.calendarIdentifier,
                sourceID: cal.source?.sourceIdentifier ?? "local",
                title: cal.title,
                color: Color(nsColor: NSColor(cgColor: cal.cgColor) ?? .systemBlue),
                isSubscribed: cal.isSubscribed,
                isReadOnly: !cal.allowsContentModifications
            )
        }
    }

    func loadEvents(start: Date, end: Date) async -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let raw = store.events(matching: predicate)
        return raw.map { ev in
            CalendarEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "",
                location: ev.location,
                notes: ev.notes,
                startDate: ev.startDate,
                endDate: ev.endDate,
                isAllDay: ev.isAllDay,
                sourceID: ev.calendar.source?.sourceIdentifier ?? "local",
                calendarID: ev.calendar.calendarIdentifier
            )
        }
    }

    func save(draft: CalendarEventDraft) async -> CalendarWriteResult {
        guard let cal = store.calendar(withIdentifier: draft.calendarID) ?? store.defaultCalendarForNewEvents else {
            return .failure("No writable calendar available.")
        }
        let event: EKEvent
        if let id = draft.id, let existing = store.event(withIdentifier: id) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
        }
        event.calendar = cal
        event.title = draft.title
        event.location = draft.location
        event.notes = draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func delete(eventID: String) async -> CalendarWriteResult {
        guard let event = store.event(withIdentifier: eventID) else {
            return .failure("Event not found.")
        }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
