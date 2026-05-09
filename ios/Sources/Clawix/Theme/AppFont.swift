import SwiftUI

// Plus Jakarta Sans wrapper.
//
// We bundle four static weights (Regular, Medium, SemiBold, Bold);
// any other Font.Weight maps to its closest match. Monospaced is
// kept on the system font: Plus Jakarta Sans has no mono cut.
enum AppFont {
    static let familyRegular  = "PlusJakartaSans-Regular"
    static let familyMedium   = "PlusJakartaSans-Medium"
    static let familySemibold = "PlusJakartaSans-SemiBold"
    static let familyBold     = "PlusJakartaSans-Bold"

    static func system(size: CGFloat,
                       weight: Font.Weight = .regular,
                       design: Font.Design = .default) -> Font {
        if design == .monospaced {
            return Font.system(size: size, weight: weight, design: .monospaced)
        }
        return Font.custom(name(for: weight), size: size)
    }

    private static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            return familyRegular
        case .medium:
            return familyMedium
        case .semibold:
            return familySemibold
        case .bold, .heavy, .black:
            return familyBold
        default:
            return familyRegular
        }
    }
}
