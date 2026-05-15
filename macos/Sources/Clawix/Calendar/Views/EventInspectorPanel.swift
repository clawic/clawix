import SwiftUI

struct EventInspectorPanel: View {
    @ObservedObject var manager: CalendarManager
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            dateLine
            if let location = event.location, !location.isEmpty {
                iconRow(icon: .link, text: location)
            }
            notesBlock
            Spacer(minLength: 0)
            footer
        }
        .padding(CalendarTokens.Spacing.inspectorInset)
        .frame(width: CalendarTokens.Geometry.inspectorWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CalendarTokens.Surface.inspector)
        .overlay(alignment: .leading) {
            Rectangle().fill(CalendarTokens.Divider.seam).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(manager.color(forCalendarID: event.calendarID))
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.system(size: CalendarTokens.TypeSize.inspectorEventTitle, weight: .semibold))
                    .foregroundColor(CalendarTokens.Ink.primary)
                    .lineLimit(2)
                if let source = manager.source(forCalendarID: event.calendarID) {
                    Text(source.title)
                        .font(.system(size: 11))
                        .foregroundColor(CalendarTokens.Ink.secondary)
                }
            }
            Spacer()
            Button { manager.selectedEventID = nil } label: {
                LucideIcon(.x, size: 12)
                    .foregroundColor(CalendarTokens.Ink.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var dateLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(longDate(event.startDate))
                .font(.system(size: CalendarTokens.TypeSize.inspectorLabel))
                .foregroundColor(CalendarTokens.Ink.primary)
            if event.isAllDay {
                Text("All day")
                    .font(.system(size: 11))
                    .foregroundColor(CalendarTokens.Ink.secondary)
            } else {
                Text("\(timeOnly(event.startDate)) – \(timeOnly(event.endDate))")
                    .font(.system(size: 11))
                    .foregroundColor(CalendarTokens.Ink.secondary)
            }
        }
    }

    private func iconRow(icon: LucideIcon.Kind, text: String) -> some View {
        HStack(spacing: 8) {
            LucideIcon(icon, size: 12)
                .foregroundColor(CalendarTokens.Ink.secondary)
                .frame(width: 18, alignment: .center)
            Text(text)
                .font(.system(size: CalendarTokens.TypeSize.inspectorLabel))
                .foregroundColor(CalendarTokens.Ink.primary)
            Spacer()
        }
    }

    @ViewBuilder
    private var notesBlock: some View {
        if let notes = event.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    LucideIcon(.fileText, size: 12)
                        .foregroundColor(CalendarTokens.Ink.secondary)
                        .frame(width: 18)
                    Text("Notes")
                        .font(.system(size: 11))
                        .foregroundColor(CalendarTokens.Ink.secondary)
                }
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundColor(CalendarTokens.Ink.primary)
                    .padding(.leading, 26)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { manager.startEdit(event: event) } label: {
                Text("Edit")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CalendarTokens.Ink.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CalendarTokens.Surface.window)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(CalendarTokens.Divider.hairline, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            Button { Task { await manager.deleteEvent(event) } } label: {
                Text("Delete")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.23))
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CalendarTokens.Surface.window)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(CalendarTokens.Divider.hairline, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = manager.localeForDisplay
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: d)
    }

    private func timeOnly(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = manager.localeForDisplay
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: d)
    }
}
