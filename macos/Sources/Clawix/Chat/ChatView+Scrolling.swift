import AppKit
import SwiftUI
import ClawixCore

struct ChatScrollDeclarativeAnchors: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .defaultScrollAnchor(.top, for: .alignment)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
        } else {
            content
        }
    }
}

struct ChatScrollUpSentinel: ViewModifier {
    let threshold: CGFloat
    let onTrigger: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: Bool.self) { geom in
                let realOverflow = geom.contentSize.height
                    > geom.containerSize.height - geom.contentInsets.top - geom.contentInsets.bottom + 1
                return geom.contentOffset.y < threshold && realOverflow
            } action: { wasNearTop, isNearTop in
                if isNearTop && !wasNearTop {
                    onTrigger()
                }
            }
        } else {
            content
        }
    }
}

struct WorkPillAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct BranchPillAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
