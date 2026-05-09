import SwiftUI
import AppKit

/// Thin draggable splitter that sits between two adjacent panes inside
/// a `.split` node. Width 6pt, only paints visibly on hover, and
/// reports the new left-side weight back to the store via `onAdjust`.
///
/// Unlike `TerminalResizeHandle` (which moves a sidebar boundary and
/// snaps closed), this splitter only mutates pane weights — there's no
/// close threshold and no `@AppStorage` persistence; the split tree is
/// the source of truth.
struct TerminalPaneSplitter: View {
    enum Axis { case horizontal, vertical }

    let axis: Axis
    let totalSize: CGFloat
    let leftWeight: Double
    let rightWeight: Double
    let onAdjust: (Double) -> Void

    @State private var hovered = false
    @State private var dragStart: CGFloat? = nil
    @State private var weightAtDragStart: Double = 0

    private var thickness: CGFloat { 6 }

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(hovered ? 0.18 : 0.0))
            .frame(
                width: axis == .horizontal ? thickness : nil,
                height: axis == .horizontal ? nil : thickness
            )
            .contentShape(Rectangle())
            .onHover { hovered = $0; updateCursor(hovered) }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = axis == .horizontal ? value.startLocation.x : value.startLocation.y
                            weightAtDragStart = leftWeight
                        }
                        let current = axis == .horizontal ? value.location.x : value.location.y
                        let delta = current - (dragStart ?? current)
                        let totalWeight = leftWeight + rightWeight
                        let totalPx = totalSize > 0 ? totalSize : 1
                        let newLeft = weightAtDragStart + (Double(delta) / Double(totalPx)) * totalWeight
                        onAdjust(max(0.1, min(totalWeight - 0.1, newLeft)))
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
    }

    private func updateCursor(_ hovered: Bool) {
        if hovered {
            (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
