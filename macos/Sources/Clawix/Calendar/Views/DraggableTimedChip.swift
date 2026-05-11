import SwiftUI

struct DraggableTimedChip: View {
    @ObservedObject var manager: CalendarManager
    let event: CalendarEvent
    let rowHeight: CGFloat

    @State private var dragOffset: CGFloat = 0
    @State private var resizeDelta: CGFloat = 0
    @State private var isResizing: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            EventChip(event: event,
                       color: manager.color(forCalendarID: event.calendarID),
                       style: .timedBar)
                .offset(y: dragOffset)
                .frame(maxHeight: .infinity)
            resizeHandle
        }
        .contentShape(Rectangle())
        .onTapGesture {
            manager.selectedEventID = event.id
        }
        .simultaneousGesture(moveGesture)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if isResizing { return }
                let snapped = snap(value.translation.height)
                dragOffset = snapped
            }
            .onEnded { value in
                let translation = value.translation.height
                if abs(translation) < 6 {
                    manager.selectedEventID = event.id
                    dragOffset = 0
                    return
                }
                let snapped = snap(translation)
                let minutes = Int(snapped / rowHeight * 60)
                dragOffset = 0
                guard minutes != 0 else { return }
                Task { await manager.moveEvent(event, by: minutes) }
            }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        isResizing = true
                        resizeDelta = snap(value.translation.height)
                    }
                    .onEnded { value in
                        let snapped = snap(value.translation.height)
                        let minutes = Int(snapped / rowHeight * 60)
                        resizeDelta = 0
                        isResizing = false
                        guard minutes != 0 else { return }
                        Task { await manager.resizeEvent(event, deltaEndMinutes: minutes) }
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        let perQuarter = rowHeight / 4
        return (value / perQuarter).rounded() * perQuarter
    }
}
