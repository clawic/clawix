import SwiftUI

struct EventChip: View {
    let event: CalendarEvent
    let color: Color
    let style: Style
    @State private var hovered: Bool = false

    enum Style {
        case monthRow
        case timedBar
        case compact
    }

    var body: some View {
        switch style {
        case .monthRow:   monthRow
        case .timedBar:   timedBar
        case .compact:    compact
        }
    }

    private var monthRow: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(timeOnly(event.startDate))
                .font(.system(size: CalendarTokens.TypeSize.eventTime))
                .foregroundColor(CalendarTokens.Ink.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(event.title)
                .font(.system(size: CalendarTokens.TypeSize.eventTitle, weight: .medium))
                .foregroundColor(CalendarTokens.Ink.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 18)
        .background(
            RoundedRectangle(cornerRadius: CalendarTokens.Radius.eventChip, style: .continuous)
                .fill(color.opacity(hovered ? 0.28 : 0.18))
        )
        .onHover { hovered = $0 }
        .animation(CalendarTokens.Motion.eventHover, value: hovered)
    }

    private var timedBar: some View {
        HStack(alignment: .top, spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: CalendarTokens.TypeSize.eventTitle, weight: .medium))
                    .foregroundColor(CalendarTokens.Ink.primary)
                    .lineLimit(2)
                Text("\(timeOnly(event.startDate)) – \(timeOnly(event.endDate))")
                    .font(.system(size: CalendarTokens.TypeSize.eventTime))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: CalendarTokens.Radius.eventChip, style: .continuous)
                .fill(color.opacity(hovered ? 0.28 : 0.18))
        )
        .clipShape(RoundedRectangle(cornerRadius: CalendarTokens.Radius.eventChip, style: .continuous))
        .onHover { hovered = $0 }
        .animation(CalendarTokens.Motion.eventHover, value: hovered)
    }

    private var compact: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(event.title)
                .font(.system(size: CalendarTokens.TypeSize.eventTime, weight: .medium))
                .foregroundColor(CalendarTokens.Ink.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 14)
    }

    private func timeOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = Locale.current.identifier.hasPrefix("en") ? "h:mma" : "HH:mm"
        return f.string(from: date)
    }
}
