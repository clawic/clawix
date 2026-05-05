import SwiftUI
import CoreText

// Manrope wrapper for all body copy. Mirrors the iOS-side BodyFont so
// the same call sites work cross-platform.
//
// The bundled file is the variable Manrope; macOS exposes its named
// instances as `Manrope-{Regular,Medium,SemiBold,Bold}` once the font
// is registered via CoreText. Monospaced design keeps the platform
// mono since Manrope has no mono cut.
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

    // Bumped one step up vs. iOS so the macOS UI reads a touch firmer.
    // Manrope's variable font exposes ExtraBold (800) as its heaviest
    // named instance, used here for everything semibold and above.
    private static func suffix(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            return "SemiBold"
        case .medium:
            return "Bold"
        case .semibold, .bold, .heavy, .black:
            return "ExtraBold"
        default:
            return "SemiBold"
        }
    }

    // SwiftPM bundles resources into a nested module bundle, so the
    // top-level Info.plist can't reach the file via ATSApplicationFontsPath.
    // Register at process start instead. Idempotent: CTFontManager
    // returns `alreadyRegistered` on subsequent calls and we ignore it.
    private static let registerOnce: Void = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.lowercased().hasPrefix("manrope") {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }()

    static func register() {
        _ = registerOnce
    }
}
