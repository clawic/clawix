import SwiftUI
import UniformTypeIdentifiers

/// Single terminal pane: emulator view + focus handling + per-pane
/// floating controls + context menu + drag-and-drop targets (tab chips
/// dropped here dock as a split). Lives at every leaf in the split tree
/// rendered by `TerminalSplitView`.
struct TerminalLeafHost: View {
    @EnvironmentObject var store: TerminalSessionStore
    let chatId: UUID
    let tabId: UUID
    let leaf: TerminalSplitNode.LeafID
    let isActive: Bool

    @State private var dockZone: TerminalSplitView.DockZone?
    @State private var paneSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                emulatorLayer
                if !isActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.setFocusedLeaf(chatId: chatId, tabId: tabId, leafId: leaf.id)
                        }
                }
                dockPreview
                if isActive {
                    TerminalPaneControls(
                        onSplitRight: {
                            store.splitLeaf(chatId: chatId, tabId: tabId, leafId: leaf.id, direction: .horizontal)
                        },
                        onSplitDown: {
                            store.splitLeaf(chatId: chatId, tabId: tabId, leafId: leaf.id, direction: .vertical)
                        },
                        onClose: {
                            store.closeLeaf(chatId: chatId, tabId: tabId, leafId: leaf.id)
                        }
                    )
                    .padding(.top, 6)
                    .padding(.trailing, 8)
                    .allowsHitTesting(true)
                }
            }
            .onAppear { paneSize = proxy.size }
            .onChange(of: proxy.size) { _, newValue in paneSize = newValue }
            .onDrop(
                of: [TerminalTabPayload.utType],
                delegate: PaneDockDropDelegate(
                    chatId: chatId,
                    destTabId: tabId,
                    destLeafId: leaf.id,
                    store: store,
                    paneSize: { paneSize },
                    dockZone: $dockZone
                )
            )
            .contextMenu {
                Button("Split Right") {
                    store.splitLeaf(chatId: chatId, tabId: tabId, leafId: leaf.id, direction: .horizontal)
                }
                Button("Split Down") {
                    store.splitLeaf(chatId: chatId, tabId: tabId, leafId: leaf.id, direction: .vertical)
                }
                Divider()
                Button("Close Pane") {
                    store.closeLeaf(chatId: chatId, tabId: tabId, leafId: leaf.id)
                }
            }
        }
    }

    @ViewBuilder
    private var emulatorLayer: some View {
        if let session = store.session(for: leaf.id) {
            TerminalEmulatorView(
                session: session,
                isFocused: isActive,
                onFocus: { store.setFocusedLeaf(chatId: chatId, tabId: tabId, leafId: leaf.id) }
            )
        } else {
            ZStack {
                Color.black
                Text("Shell unavailable")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Palette.textSecondary)
            }
        }
    }

    /// Translucent half-pane that previews where the dragged tab will
    /// land. Mirrors VS Code's dock preview.
    @ViewBuilder
    private var dockPreview: some View {
        if let zone = dockZone {
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                let rect: CGRect = {
                    switch zone {
                    case .left:   return CGRect(x: 0, y: 0, width: w / 2, height: h)
                    case .right:  return CGRect(x: w / 2, y: 0, width: w / 2, height: h)
                    case .top:    return CGRect(x: 0, y: 0, width: w, height: h / 2)
                    case .bottom: return CGRect(x: 0, y: h / 2, width: w, height: h / 2)
                    }
                }()
                Color.white.opacity(0.12)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.32), lineWidth: 0.7)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY),
                        alignment: .topLeading
                    )
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

private struct PaneDockDropDelegate: DropDelegate {
    let chatId: UUID
    let destTabId: UUID
    let destLeafId: UUID
    let store: TerminalSessionStore
    let paneSize: () -> CGSize
    @Binding var dockZone: TerminalSplitView.DockZone?

    func dropEntered(info: DropInfo) {
        dockZone = zone(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dockZone = zone(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dockZone = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dockZone = nil }
        guard let payload = TerminalTabPayload.decode(from: info) else { return false }
        // Dropping a tab on its own pane is a no-op: there's nothing to
        // dock against. `moveTabAsSplit` guards on tab id, so this is
        // belt-and-braces for the obvious "drop where you started" case.
        let leaves = store.tabs(for: chatId).first(where: { $0.id == payload.tabId })?.layout.leaves ?? []
        if leaves.contains(where: { $0.id == destLeafId }) { return false }
        guard let resolved = zone(for: info) else { return false }
        let direction: TerminalSplitNode.SplitDirection
        let insertBefore: Bool
        switch resolved {
        case .left:   direction = .horizontal; insertBefore = true
        case .right:  direction = .horizontal; insertBefore = false
        case .top:    direction = .vertical;   insertBefore = true
        case .bottom: direction = .vertical;   insertBefore = false
        }
        store.moveTabAsSplit(
            chatId: chatId,
            sourceTabId: payload.tabId,
            destTabId: destTabId,
            destLeafId: destLeafId,
            direction: direction,
            insertBefore: insertBefore
        )
        return true
    }

    private func zone(for info: DropInfo) -> TerminalSplitView.DockZone? {
        let size = paneSize()
        guard size.width > 0, size.height > 0 else { return nil }
        let p = info.location
        let relX = p.x / size.width
        let relY = p.y / size.height
        // Distance to each edge in normalized units. Smallest wins so
        // the user always lands on the closest dock side.
        let distLeft = relX
        let distRight = 1 - relX
        let distTop = relY
        let distBottom = 1 - relY
        let minDist = min(distLeft, distRight, distTop, distBottom)
        switch minDist {
        case distLeft:   return .left
        case distRight:  return .right
        case distTop:    return .top
        default:         return .bottom
        }
    }
}
