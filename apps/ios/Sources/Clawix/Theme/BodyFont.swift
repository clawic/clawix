import SwiftUI

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

    private static func suffix(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            return "Regular"
        case .medium:
            return "Medium"
        case .semibold:
            return "SemiBold"
        case .bold, .heavy, .black:
            return "Bold"
        default:
            return "Regular"
        }
    }
}
