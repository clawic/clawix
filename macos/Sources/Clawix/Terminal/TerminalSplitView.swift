import SwiftUI
import UniformTypeIdentifiers

/// Recursive renderer for the split tree of a single tab. Each leaf
/// hosts a `TerminalEmulatorView`; each `.split` lays its children out
/// in an `HStack`/`VStack` (depending on direction) interleaved with
/// `TerminalPaneSplitter` handles.
struct TerminalSplitView: View {
    @EnvironmentObject var store: TerminalSessionStore
    let chatId: UUID
    let tabId: UUID
    let node: TerminalSplitNode
    let focusedLeafId: UUID?
    /// Path of child indices from the tab root down to `node`. The root
    /// renderer passes `[]`; recursive call sites append the index.
    let path: [Int]

    /// Quadrant of a leaf where a dragged tab will dock if dropped now.
    /// Drives the translucent overlay that previews the resulting split
    /// before the user releases the mouse.
    enum DockZone: Equatable {
        case left, right, top, bottom
    }

    var body: some View {
        GeometryReader { proxy in
            content(in: proxy.size)
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch node {
        case .leaf(let leaf):
            leafView(leaf)
        case .split(let direction, let children, let weights):
            splitContainer(direction: direction,
                           children: children,
                           weights: weights,
                           size: size)
        }
    }

    @ViewBuilder
    private func leafView(_ leaf: TerminalSplitNode.LeafID) -> some View {
        TerminalLeafHost(
            chatId: chatId,
            tabId: tabId,
            leaf: leaf,
            isActive: focusedLeafId == leaf.id
        )
    }

    @ViewBuilder
    private func splitContainer(direction: TerminalSplitNode.SplitDirection,
                                children: [TerminalSplitNode],
                                weights: [Double],
                                size: CGSize) -> some View {
        let totalWeight = weights.reduce(0, +)
        let normalized: [Double] = {
            if totalWeight <= 0 || weights.count != children.count {
                let even = 1.0 / Double(max(children.count, 1))
                return Array(repeating: even, count: children.count)
            }
            return weights.map { $0 / totalWeight }
        }()
        let totalSize: CGFloat = direction == .horizontal ? size.width : size.height
        let splitterCount = max(0, children.count - 1)
        let usableSize = max(0, totalSize - CGFloat(splitterCount) * 6)

        Group {
            if direction == .horizontal {
                HStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.offset) { idx, child in
                        TerminalSplitView(
                            chatId: chatId,
                            tabId: tabId,
                            node: child,
                            focusedLeafId: focusedLeafId,
                            path: path + [idx]
                        )
                        .frame(width: usableSize * CGFloat(normalized[idx]))
                        if idx < children.count - 1 {
                            TerminalPaneSplitter(
                                axis: .horizontal,
                                totalSize: usableSize,
                                leftWeight: weights.indices.contains(idx) ? weights[idx] : normalized[idx] * totalWeight,
                                rightWeight: weights.indices.contains(idx + 1) ? weights[idx + 1] : normalized[idx + 1] * totalWeight,
                                onAdjust: { newLeft in
                                    store.adjustWeights(
                                        chatId: chatId,
                                        tabId: tabId,
                                        splitPath: path,
                                        adjacentIndex: idx,
                                        newLeftWeight: newLeft
                                    )
                                }
                            )
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.offset) { idx, child in
                        TerminalSplitView(
                            chatId: chatId,
                            tabId: tabId,
                            node: child,
                            focusedLeafId: focusedLeafId,
                            path: path + [idx]
                        )
                        .frame(height: usableSize * CGFloat(normalized[idx]))
                        if idx < children.count - 1 {
                            TerminalPaneSplitter(
                                axis: .vertical,
                                totalSize: usableSize,
                                leftWeight: weights.indices.contains(idx) ? weights[idx] : normalized[idx] * totalWeight,
                                rightWeight: weights.indices.contains(idx + 1) ? weights[idx + 1] : normalized[idx + 1] * totalWeight,
                                onAdjust: { newLeft in
                                    store.adjustWeights(
                                        chatId: chatId,
                                        tabId: tabId,
                                        splitPath: path,
                                        adjacentIndex: idx,
                                        newLeftWeight: newLeft
                                    )
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
