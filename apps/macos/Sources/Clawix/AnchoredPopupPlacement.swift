import SwiftUI
import AppKit

/// Preferred horizontal placement of an anchored popup relative to its trigger.
enum AnchoredHorizontalAlignment {
    /// Popup's leading edge sits at `buttonFrame.minX + offset`.
    case leading(offset: CGFloat = 0)
    /// Popup's trailing edge sits at `buttonFrame.maxX + offset`.
    /// `offset` is signed: negative pulls the popup further left.
    case trailing(offset: CGFloat = 0)
    /// Popup's horizontal center sits at the button's horizontal center.
    case center
}

/// Preferred vertical direction of an anchored popup relative to its trigger.
enum AnchoredVerticalDirection {
    case below
    case above
}

extension View {
    /// Positions an anchored popup over a `GeometryReader` layer, preferring
    /// `direction` but flipping to the opposite side when the popup would not
    /// fit inside the host window. Horizontal placement is clamped so the
    /// popup never escapes the visible content area.
    ///
    /// Usage:
    /// ```swift
    /// .overlayPreferenceValue(MyAnchorKey.self) { anchor in
    ///     GeometryReader { proxy in
    ///         if isOpen, let anchor {
    ///             MyMenu()
    ///                 .anchoredPopupPlacement(
    ///                     buttonFrame: proxy[anchor],
    ///                     proxy: proxy,
    ///                     horizontal: .trailing()
    ///                 )
    ///         }
    ///     }
    /// }
    /// ```
    func anchoredPopupPlacement(
        buttonFrame: CGRect,
        proxy: GeometryProxy,
        horizontal: AnchoredHorizontalAlignment,
        direction: AnchoredVerticalDirection = .below,
        gap: CGFloat = 6,
        safety: CGFloat = 16,
        sideMargin: CGFloat = 8
    ) -> some View {
        modifier(
            AnchoredPopupPlacementModifier(
                buttonFrame: buttonFrame,
                proxy: proxy,
                horizontal: horizontal,
                direction: direction,
                gap: gap,
                safety: safety,
                sideMargin: sideMargin
            )
        )
    }
}

private struct AnchoredPopupPlacementModifier: ViewModifier {
    let buttonFrame: CGRect
    let proxy: GeometryProxy
    let horizontal: AnchoredHorizontalAlignment
    let direction: AnchoredVerticalDirection
    let gap: CGFloat
    let safety: CGFloat
    let sideMargin: CGFloat

    func body(content: Content) -> some View {
        let containerFrame = proxy.frame(in: .global)
        let containerLocal = proxy.size
        let windowHeight = NSApp.keyWindow?.contentView?.bounds.height
            ?? containerFrame.maxY
        let buttonGlobalMaxY = containerFrame.minY + buttonFrame.maxY
        let buttonGlobalMinY = containerFrame.minY + buttonFrame.minY
        let availableBelow = windowHeight - buttonGlobalMaxY - safety
        let availableAbove = buttonGlobalMinY - safety

        content
            .alignmentGuide(.top) { d in
                let popupHeight = d[.bottom]
                let placeBelow = shouldPlaceBelow(
                    popupHeight: popupHeight,
                    availableBelow: availableBelow,
                    availableAbove: availableAbove
                )
                return placeBelow
                    ? -(buttonFrame.maxY + gap)
                    : popupHeight - buttonFrame.minY + gap
            }
            .alignmentGuide(.leading) { d in
                let popupWidth = d.width
                let containerWidth = containerLocal.width
                let raw: CGFloat
                switch horizontal {
                case .leading(let offset):
                    raw = buttonFrame.minX + offset
                case .trailing(let offset):
                    raw = buttonFrame.maxX + offset - popupWidth
                case .center:
                    raw = buttonFrame.midX - popupWidth / 2
                }
                let maxX = max(sideMargin, containerWidth - popupWidth - sideMargin)
                let clamped = min(max(raw, sideMargin), maxX)
                return d[.leading] - clamped
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func shouldPlaceBelow(
        popupHeight: CGFloat,
        availableBelow: CGFloat,
        availableAbove: CGFloat
    ) -> Bool {
        switch direction {
        case .below:
            if availableBelow >= popupHeight { return true }
            if availableAbove >= popupHeight { return false }
            return availableBelow >= availableAbove
        case .above:
            if availableAbove >= popupHeight { return false }
            if availableBelow >= popupHeight { return true }
            return availableAbove < availableBelow
        }
    }
}
