import Foundation

/// Recursive layout tree for the panes inside a single tab.
///
/// A tab with one shell has root `.leaf(LeafID)`. The user splitting that
/// leaf vertically produces `.split(.horizontal, [.leaf, .leaf], [0.5, 0.5])`
/// (horizontal direction = side-by-side panes laid out in an `HStack`).
/// Splits nest: re-splitting a leaf inside a split produces another
/// `.split` whose children include the original sibling leaf and the
/// new split node.
///
/// `weights` runs parallel to `children` and sums to ~1.0; the splitter
/// handle drag updates two adjacent indices simultaneously.
///
/// The enum is `Codable` so the whole tree can be persisted as a JSON
/// blob in `terminal_tabs.layout_json`. `LeafID` carries `initialCwd`
/// and `label` directly so the next launch can reincarnate sessions
/// without separately persisting `TerminalSession`s (which own NSViews
/// and PTYs and are not serializable).
indirect enum TerminalSplitNode: Equatable, Codable {
    case leaf(LeafID)
    case split(direction: SplitDirection, children: [TerminalSplitNode], weights: [Double])

    enum SplitDirection: String, Codable, Equatable {
        /// Children laid out side by side (HStack).
        case horizontal
        /// Children stacked top to bottom (VStack).
        case vertical
    }

    struct LeafID: Hashable, Codable, Equatable {
        let id: UUID
        var initialCwd: String
        var label: String
    }

    /// Walks the tree and returns every `LeafID` in left-to-right /
    /// top-to-bottom order.
    var leaves: [LeafID] {
        switch self {
        case .leaf(let leaf):
            return [leaf]
        case .split(_, let children, _):
            return children.flatMap { $0.leaves }
        }
    }

    /// Returns the first leaf id in tree order, useful for default focus.
    var firstLeafId: UUID? { leaves.first?.id }

    /// Inserts a new leaf next to the leaf with `besideId`, splitting in
    /// `direction`. If the parent of `besideId` already splits in
    /// `direction`, the new leaf joins that split as a sibling. Otherwise
    /// the original leaf is replaced by a new `.split` containing both.
    /// Weights are evenly redistributed.
    func splitting(beside besideId: UUID,
                   direction: SplitDirection,
                   newLeaf: LeafID) -> TerminalSplitNode {
        switch self {
        case .leaf(let leaf) where leaf.id == besideId:
            return .split(direction: direction,
                          children: [.leaf(leaf), .leaf(newLeaf)],
                          weights: [0.5, 0.5])
        case .leaf:
            return self
        case .split(let dir, let children, let weights):
            if dir == direction,
               let idx = children.firstIndex(where: { childContainsLeafDirectly(child: $0, leafId: besideId) }) {
                var newChildren = children
                newChildren.insert(.leaf(newLeaf), at: idx + 1)
                let even = 1.0 / Double(newChildren.count)
                return .split(direction: dir,
                              children: newChildren,
                              weights: Array(repeating: even, count: newChildren.count))
            }
            let updated = children.map { $0.splitting(beside: besideId, direction: direction, newLeaf: newLeaf) }
            return .split(direction: dir, children: updated, weights: weights)
        }
    }

    private func childContainsLeafDirectly(child: TerminalSplitNode, leafId: UUID) -> Bool {
        if case .leaf(let leaf) = child { return leaf.id == leafId }
        return false
    }

    /// Removes the leaf with `id`. Collapses any `.split` left with a
    /// single child into that child (so closing one half of a 2-pane
    /// split returns to a plain leaf). Returns `nil` if the entire tree
    /// would be empty (caller's signal to close the whole tab).
    func removingLeaf(_ id: UUID) -> TerminalSplitNode? {
        switch self {
        case .leaf(let leaf):
            return leaf.id == id ? nil : self
        case .split(let dir, let children, let weights):
            var newChildren: [TerminalSplitNode] = []
            var newWeights: [Double] = []
            for (idx, child) in children.enumerated() {
                if let kept = child.removingLeaf(id) {
                    newChildren.append(kept)
                    newWeights.append(weights[idx])
                }
            }
            if newChildren.isEmpty { return nil }
            if newChildren.count == 1 { return newChildren[0] }
            let total = newWeights.reduce(0, +)
            let normalized = total > 0
                ? newWeights.map { $0 / total }
                : Array(repeating: 1.0 / Double(newChildren.count), count: newChildren.count)
            return .split(direction: dir, children: newChildren, weights: normalized)
        }
    }

    /// Updates the leaf's `label` (or `initialCwd`) in place wherever it
    /// appears in the tree.
    func updatingLeaf(_ id: UUID, _ transform: (LeafID) -> LeafID) -> TerminalSplitNode {
        switch self {
        case .leaf(let leaf):
            return leaf.id == id ? .leaf(transform(leaf)) : self
        case .split(let dir, let children, let weights):
            let updated = children.map { $0.updatingLeaf(id, transform) }
            return .split(direction: dir, children: updated, weights: weights)
        }
    }

    /// Adjusts the weights of the children at `splitPath` (a sequence of
    /// child indices into nested `.split` nodes) so that the splitter
    /// between `index` and `index + 1` lands at `newLeftWeight`. Used by
    /// `TerminalPaneSplitter` during a live drag.
    func adjustingWeights(at splitPath: [Int],
                          adjacentIndex index: Int,
                          newLeftWeight: Double) -> TerminalSplitNode {
        guard let head = splitPath.first else {
            return adjustWeightsHere(adjacentIndex: index, newLeftWeight: newLeftWeight)
        }
        switch self {
        case .leaf:
            return self
        case .split(let dir, var children, let weights):
            children[head] = children[head].adjustingWeights(
                at: Array(splitPath.dropFirst()),
                adjacentIndex: index,
                newLeftWeight: newLeftWeight
            )
            return .split(direction: dir, children: children, weights: weights)
        }
    }

    private func adjustWeightsHere(adjacentIndex index: Int, newLeftWeight: Double) -> TerminalSplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let dir, let children, var weights):
            guard index >= 0, index + 1 < weights.count else { return self }
            let total = weights[index] + weights[index + 1]
            let clamped = max(0.1, min(total - 0.1, newLeftWeight))
            weights[index] = clamped
            weights[index + 1] = total - clamped
            return .split(direction: dir, children: children, weights: weights)
        }
    }
}
