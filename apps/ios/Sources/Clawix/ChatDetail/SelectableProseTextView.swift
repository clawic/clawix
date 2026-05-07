import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Wraps a UITextView so a contiguous group of assistant prose blocks
// (paragraphs, headings, bullet/numbered lists) renders as a single
// selectable run. The user can long-press anywhere in the agent reply
// and drag the selection across blocks like in a normal page or word
// processor — SwiftUI Text only supports per-Text selection on iOS,
// which forces this UIKit detour.
//
// Code blocks are intentionally NOT included here: they keep their
// fenced chrome with the language label and copy button, and their
// own `.textSelection(.enabled)` UITextView underneath.

#if canImport(UIKit)

struct SelectableProseTextView: UIViewRepresentable {
    let blocks: [AssistantBlock]

    func makeUIView(context: Context) -> SelfSizingTextView {
        // Build the text stack with an explicit NSTextStorage /
        // NSLayoutManager so we stay on TextKit 1: that lets us
        // enumerate glyph rects per attributed run and overlay
        // continuous-corner pill views behind inline code spans
        // (mirrors the macOS InlineCode look). The rendering is done
        // by `SelfSizingTextView` itself, not the layout manager,
        // because SwiftUI-style `style: .continuous` corners come
        // from `layer.cornerCurve = .continuous` on a UIView.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer()
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(container)

        let tv = SelfSizingTextView(frame: .zero, textContainer: container)
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.isSelectable = true
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.adjustsFontForContentSizeCategory = false
        tv.dataDetectorTypes = [.link]
        tv.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        tv.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: SelfSizingTextView, context: Context) {
        let attributed = AssistantProseAttributedBuilder.build(blocks: blocks)
        if !tv.attributedText.isEqual(to: attributed) {
            tv.attributedText = attributed
            tv.invalidateIntrinsicContentSize()
        }
    }
}

/// UITextView that grows to its natural content height inside a
/// SwiftUI VStack. With `isScrollEnabled = false`, UIKit lays the
/// text out in `textContainer`, but SwiftUI still needs an
/// `intrinsicContentSize` once the parent has handed us a real width.
final class SelfSizingTextView: UITextView {
    private var lastWidth: CGFloat = -1
    private var pillViews: [UIView] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        layoutInlineCodePills()
    }

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric,
                          height: UIView.noIntrinsicMetric)
        }
        let size = sizeThatFits(CGSize(width: bounds.width,
                                       height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }

    /// Overlays a continuous-corner UIView behind every run flagged
    /// with `inlineCodePillKey`. Rects come straight from the layout
    /// manager so they track wraps correctly when an inline code
    /// span spills across two lines. Views are pooled so streaming
    /// updates don't churn the subview list.
    private func layoutInlineCodePills() {
        let storage = textStorage
        let lm = layoutManager
        let container = textContainer

        var rects: [CGRect] = []
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(inlineCodePillKey,
                                   in: fullRange,
                                   options: []) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let runGlyphRange = lm.glyphRange(forCharacterRange: range,
                                              actualCharacterRange: nil)
            lm.enumerateLineFragments(forGlyphRange: runGlyphRange) {
                _, _, _, lineGlyphs, _ in
                let intersection = NSIntersectionRange(runGlyphRange, lineGlyphs)
                guard intersection.length > 0 else { return }
                var rect = lm.boundingRect(forGlyphRange: intersection,
                                           in: container)
                rect.origin.x += self.textContainerInset.left
                rect.origin.y += self.textContainerInset.top
                // Inflate horizontally so the glyph isn't glued to
                // the pill edges. Vertically we shrink the pill
                // inside the line fragment so adjacent lines don't
                // overlap, then extend the top edge by 1pt so the
                // text reads visually centered (the typographic
                // baseline sits a hair below the geometric center
                // otherwise). Combined with `.baselineOffset = 1`
                // on the inline code run, this mirrors the macOS
                // InlineCode look.
                rect = rect.insetBy(dx: -7, dy: 2.5)
                rect.origin.y -= 1
                rect.size.height += 1
                rects.append(rect)
            }
        }

        while pillViews.count < rects.count {
            let v = UIView()
            v.isUserInteractionEnabled = false
            v.backgroundColor = UIColor.white.withAlphaComponent(0.15)
            v.layer.cornerCurve = .continuous
            v.layer.cornerRadius = 7
            insertSubview(v, at: 0)
            pillViews.append(v)
        }
        for (i, v) in pillViews.enumerated() {
            if i < rects.count {
                v.frame = rects[i]
                v.isHidden = false
            } else {
                v.isHidden = true
            }
        }
    }
}

/// Marker attribute set on inline code runs by `proseAttributed`.
/// `SelfSizingTextView.layoutInlineCodePills()` enumerates these
/// ranges and overlays a continuous-corner pill view behind each
/// occurrence, matching the macOS InlineCode look.
let inlineCodePillKey = NSAttributedString.Key("clawixInlineCodePill")

enum AssistantProseAttributedBuilder {
    static func build(blocks: [AssistantBlock]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (idx, block) in blocks.enumerated() {
            if idx > 0 {
                let prevWasList: Bool
                switch blocks[idx - 1] {
                case .bulletList, .numberedList: prevWasList = true
                default: prevWasList = false
                }
                result.append(prevWasList ? listEndSpacer() : blockSpacer())
            }
            switch block {
            case .heading(let level, let line):
                result.append(headingAttributed(level: level, line: line))
            case .paragraph(let line):
                result.append(proseAttributed(
                    line: line,
                    font: bodyFont,
                    paragraphStyle: bodyParagraphStyle()
                ))
            case .bulletList(let items):
                for (i, item) in items.enumerated() {
                    if i > 0 {
                        result.append(listItemSpacer())
                    }
                    result.append(listLine(kind: .bullet, item: item))
                }
            case .numberedList(let start, let items):
                for (i, item) in items.enumerated() {
                    if i > 0 {
                        result.append(listItemSpacer())
                    }
                    result.append(listLine(
                        kind: .numbered("\(start + i)."),
                        item: item
                    ))
                }
            case .codeBlock:
                continue
            }
        }
        return result
    }

    // MARK: Style tokens

    private static var bodyFont: UIFont {
        // Typography.chatBodyFont = BodyFont.system(size: 16.5),
        // which maps to Manrope-Medium (BodyFont bumps the requested
        // weight one step up; .regular → Medium).
        UIFont(name: "Manrope-Medium", size: 16.5)
            ?? UIFont.systemFont(ofSize: 16.5)
    }

    private static var inlineCodeFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    }

    private static var inlineCodeColor: UIColor {
        UIColor(white: 0.94, alpha: 1)
    }

    private static var textPrimary: UIColor { .white }

    private static func bodyParagraphStyle() -> NSParagraphStyle {
        let s = NSMutableParagraphStyle()
        s.lineSpacing = 3
        s.lineBreakMode = .byWordWrapping
        return s
    }

    private static func listParagraphStyle() -> NSParagraphStyle {
        let s = NSMutableParagraphStyle()
        s.lineSpacing = 3
        s.lineBreakMode = .byWordWrapping
        s.firstLineHeadIndent = 0
        s.headIndent = 22
        s.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
        s.defaultTabInterval = 22
        return s
    }

    private static func headingFont(_ level: Int) -> UIFont {
        switch level {
        case 1:  return UIFont(name: "Manrope-Bold", size: 22)
            ?? UIFont.boldSystemFont(ofSize: 22)
        case 2:  return UIFont(name: "Manrope-Bold", size: 19)
            ?? UIFont.boldSystemFont(ofSize: 19)
        case 3:  return UIFont(name: "Manrope-SemiBold", size: 17)
            ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        default: return UIFont(name: "Manrope-SemiBold", size: 16)
            ?? UIFont.systemFont(ofSize: 16, weight: .semibold)
        }
    }

    // MARK: Block builders

    // "\n\n" so the first newline terminates the previous block's
    // paragraph and the second creates a real EMPTY paragraph whose
    // height we can pin. A single "\n" would only be the terminator
    // and contribute no extra vertical space, which is why the gap
    // between paragraphs / lists / headings used to look collapsed.
    private static func blockSpacer() -> NSAttributedString {
        return spacerParagraph(height: 18)
    }

    // Larger gap when transitioning OUT of a bullet/numbered list into
    // the next block, since the list's bottom marker (last item) reads
    // as part of the list and needs extra breathing room before the
    // following paragraph / heading / code block.
    private static func listEndSpacer() -> NSAttributedString {
        return spacerParagraph(height: 26)
    }

    private static func listItemSpacer() -> NSAttributedString {
        return spacerParagraph(height: 6)
    }

    private static func spacerParagraph(height: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return NSAttributedString(string: "\n\n", attributes: [
            .font: UIFont.systemFont(ofSize: 1),
            .paragraphStyle: style,
        ])
    }

    private static func headingAttributed(
        level: Int,
        line: AttributedString
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.lineBreakMode = .byWordWrapping
        if level <= 2 {
            style.paragraphSpacingBefore = 4
        }
        return proseAttributed(
            line: line,
            font: headingFont(level),
            paragraphStyle: style,
            forceWeight: .semibold
        )
    }

    enum ListMarkerKind {
        case bullet
        case numbered(String)
    }

    private static func listLine(
        kind: ListMarkerKind,
        item: AttributedString
    ) -> NSAttributedString {
        let style = listParagraphStyle()
        let line = NSMutableAttributedString()
        switch kind {
        case .bullet:
            // "●" at a small font size + baselineOffset so it reads as
            // a 5-6pt filled circle vertically centered on the body
            // text, mirroring the Circle(width: 5, height: 5) the Mac
            // chat uses for bullets.
            line.append(NSAttributedString(string: "●\t", attributes: [
                .font: UIFont.systemFont(ofSize: 7, weight: .black),
                .foregroundColor: textPrimary,
                .baselineOffset: 3.5,
                .paragraphStyle: style,
            ]))
        case .numbered(let marker):
            line.append(NSAttributedString(string: "\(marker)\t", attributes: [
                .font: bodyFont,
                .foregroundColor: textPrimary,
                .paragraphStyle: style,
                .kern: -0.2,
            ]))
        }
        line.append(proseAttributed(
            line: item,
            font: bodyFont,
            paragraphStyle: style
        ))
        return line
    }

    /// Walks an inline `AttributedString` from the markdown parser and
    /// converts each run into NSAttributedString attributes. Inline
    /// code runs (`run.inlinePresentationIntent.contains(.code)`) get
    /// the monospaced font + warm-white tint. Bold / italic runs
    /// rebuild the font with the matching named Manrope cut when one
    /// exists, falling back to the system descriptor traits.
    private static func proseAttributed(
        line: AttributedString,
        font: UIFont,
        paragraphStyle: NSParagraphStyle,
        forceWeight: UIFont.Weight? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in line.runs {
            let raw = String(line[run.range].characters)
            let intent = run.inlinePresentationIntent
            let isInlineCode = intent?.contains(.code) == true

            var attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: textPrimary,
                .paragraphStyle: paragraphStyle,
                .kern: -0.2,
            ]
            if isInlineCode {
                attrs[.font] = inlineCodeFont
                attrs[.foregroundColor] = inlineCodeColor
                attrs[inlineCodePillKey] = true
                // Lift the glyph up so the text reads visually
                // centered inside the pill instead of sitting on
                // the typographic baseline (which sits below the
                // geometric center of the line fragment).
                attrs[.baselineOffset] = 1.0
            } else {
                attrs[.font] = applyInlineIntent(
                    font: font,
                    intent: intent,
                    forceWeight: forceWeight
                )
            }
            if let url = run.link {
                attrs[.link] = url
            }
            result.append(NSAttributedString(string: raw, attributes: attrs))
        }

        // Insert breathing room on each side of every inline code
        // span so the pill never touches the adjacent words.
        //
        // The kern attribute always lands on a NON-code character so
        // it never bleeds into the pill's own bounding rect:
        //   - entering code: kern on the char immediately before the
        //     pill (e.g. the space before `foo`), pushing the pill
        //     and everything past it rightward.
        //   - exiting code: kern on the first non-code char AFTER
        //     the pill (e.g. the space following `foo`), which
        //     pushes the next word further from the pill without
        //     affecting where the layout manager thinks the code
        //     run ends.
        let length = result.length
        if length > 1 {
            let codeBoundaryKern: CGFloat = 10
            for i in (1..<length).reversed() {
                let curIsCode = (result.attribute(inlineCodePillKey,
                                                  at: i,
                                                  effectiveRange: nil) as? Bool) == true
                let prevIsCode = (result.attribute(inlineCodePillKey,
                                                   at: i - 1,
                                                   effectiveRange: nil) as? Bool) == true
                guard curIsCode != prevIsCode else { continue }
                let kernIndex = curIsCode ? i - 1 : i
                result.addAttribute(.kern,
                                    value: codeBoundaryKern,
                                    range: NSRange(location: kernIndex, length: 1))
            }
        }
        return result
    }

    private static func applyInlineIntent(
        font: UIFont,
        intent: InlinePresentationIntent?,
        forceWeight: UIFont.Weight?
    ) -> UIFont {
        let bold = intent?.contains(.stronglyEmphasized) == true
        let italic = intent?.contains(.emphasized) == true

        if bold {
            if let manropeBold = UIFont(name: "Manrope-Bold", size: font.pointSize) {
                return italicized(manropeBold, italic: italic)
            }
        }
        if forceWeight == .semibold {
            if let manropeSemi = UIFont(name: "Manrope-SemiBold", size: font.pointSize) {
                return italicized(manropeSemi, italic: italic)
            }
        }
        if !bold && !italic { return font }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
        return font
    }

    private static func italicized(_ font: UIFont, italic: Bool) -> UIFont {
        guard italic else { return font }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
        return font
    }
}

#endif
