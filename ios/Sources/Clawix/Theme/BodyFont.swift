import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Manrope wrapper for all body copy.
//
// The bundled file is the variable Manrope; iOS exposes its named
// instances as `Manrope-{Regular,Medium,SemiBold,Bold}`. Monospaced
// design keeps the platform mono since Manrope has no mono cut.
enum BodyFont {
    private static let familyPrefix = "Manrope"

    static func system(size: CGFloat,
                       weight: Font.Weight = .regular,
                       design: Font.Design = .default) -> Font {
        if design == .monospaced {
            return Font.system(size: size, weight: weight, design: .monospaced)
        }
        return Font.custom("\(familyPrefix)-\(suffix(for: weight))", size: size)
    }

    /// Variable-axis variant for the rare cases that need a weight
    /// that doesn't match a named instance (e.g. 450 between Regular
    /// and Medium). On non-UIKit platforms it falls back to the
    /// nearest named cut.
    static func manrope(size: CGFloat, wght: CGFloat) -> Font {
        #if canImport(UIKit)
        let wghtTag = 0x77676874 // 'wght'
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: "\(familyPrefix)-Regular",
            UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"): [wghtTag: wght],
        ])
        return Font(UIFont(descriptor: descriptor, size: size))
        #else
        let nearest: String
        switch wght {
        case ..<350: nearest = "Light"
        case ..<450: nearest = "Regular"
        case ..<550: nearest = "Medium"
        case ..<650: nearest = "SemiBold"
        default: nearest = "Bold"
        }
        return Font.custom("\(familyPrefix)-\(nearest)", size: size)
        #endif
    }

    private static func suffix(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            return "Medium"
        case .medium:
            return "SemiBold"
        case .semibold, .bold, .heavy, .black:
            return "Bold"
        default:
            return "Medium"
        }
    }
}
