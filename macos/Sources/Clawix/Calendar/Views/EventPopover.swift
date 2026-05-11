import SwiftUI

struct EventPopover: View {
    @ObservedObject var manager: CalendarManager
    let event: CalendarEvent
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(manager.color(forCalendarID: event.calendarID))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title.isEmpty ? "Untitled" : event.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(CalendarTokens.Ink.primary)
                        .lineLimit(2)
                    Text(dateLine)
                        .font(.system(size: 11))
                        .foregroundColor(CalendarTokens.Ink.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    LucideIcon(.x, size: 11)
                        .foregroundColor(CalendarTokens.Ink.secondary)
                }
                .buttonStyle(.plain)
            }
            if let loc = event.location, !loc.isEmpty {
                HStack(spacing: 6) {
                    LucideIcon(.link, size: 11)
                        .foregroundColor(CalendarTokens.Ink.secondary)
                    Text(loc)
                        .font(.system(size: 12))
                        .foregroundColor(CalendarTokens.Ink.primary)
                }
            }
            if let notes = event.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .lineLimit(4)
            }
            Divider().opacity(0.3)
            HStack(spacing: 8) {
                Button { manager.startEdit(event: event) } label: {
                    Text("Edit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CalendarTokens.Ink.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                Button { Task { await manager.deleteEvent(event) } } label: {
                    Text("Delete")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.23))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.135))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)
        )
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = manager.localeForDisplay
        if event.isAllDay {
            f.dateStyle = .full
            f.timeStyle = .none
            return f.string(from: event.startDate) + " · All day"
        }
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: event.startDate) + " – " + shortTime(event.endDate)
    }

    private func shortTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = manager.localeForDisplay
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: d)
    }
}
