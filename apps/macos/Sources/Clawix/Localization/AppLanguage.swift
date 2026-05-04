import Foundation
import SwiftUI

/// Runtime language switching for the app.
///
/// SwiftPM ships `Localizable.xcstrings` straight into the resource
/// bundle (no `.lproj/.strings` codegen on `swift build`). Foundation
/// resolves keys against that file using `Bundle.preferredLocalizations`,
/// which in turn reads the `AppleLanguages` user-default. Overriding that
/// default before any UI renders is what makes `String(localized:bundle:)`
/// pick a different translation at runtime, without restarting the app.
///
/// In parallel we publish the chosen `Locale` through `AppLocale.current`
/// and the SwiftUI `\.locale` environment so `Text("…")` literals also
/// re-render when the user picks a new language from Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish        = "es"
    case english        = "en"
    case french         = "fr"
    case german         = "de"
    case italian        = "it"
    case portugueseBR   = "pt-BR"
    case japanese       = "ja"
    case chineseSimp    = "zh-Hans"
    case korean         = "ko"
    case russian        = "ru"

    var id: String { rawValue }

    /// Native name shown inside the dropdown row (matches Apple's own
    /// "Language" pickers: each option in its own language).
    var displayName: String {
        switch self {
        case .spanish:      return "Spanish"
        case .english:      return "English"
        case .french:       return "Français"
        case .german:       return "Deutsch"
        case .italian:      return "Italiano"
        case .portugueseBR: return "Português (Brasil)"
        case .japanese:     return "日本語"
        case .chineseSimp:  return "简体中文"
        case .korean:       return "한국어"
        case .russian:      return "Русский"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var speechRecognitionLocale: Locale {
        switch self {
        case .spanish:      return Locale(identifier: "es-ES")
        case .english:      return Locale(identifier: "en-US")
        case .french:       return Locale(identifier: "fr-FR")
        case .german:       return Locale(identifier: "de-DE")
        case .italian:      return Locale(identifier: "it-IT")
        case .portugueseBR: return Locale(identifier: "pt-BR")
        case .japanese:     return Locale(identifier: "ja-JP")
        case .chineseSimp:  return Locale(identifier: "zh-CN")
        case .korean:       return Locale(identifier: "ko-KR")
        case .russian:      return Locale(identifier: "ru-RU")
        }
    }

    /// Resolves to the `<lang>.lproj` sub-bundle inside the package's
    /// resource bundle. SwiftPM lowercases lproj folder names on copy
    /// (`pt-BR.lproj` → `pt-br.lproj`), so we try the canonical BCP-47
    /// form first and the lowercased form as a fallback. Falls back to
    /// the package bundle (source language) if no lproj is found, e.g.
    /// when the user is on the dev source language ("es") or someone
    /// shipped without re-running compile_xcstrings.py.
    var bundle: Bundle {
        let pkg = AppLocale.packageBundle
        for candidate in [rawValue, rawValue.lowercased()] {
            if let path = pkg.path(forResource: candidate, ofType: "lproj"),
               let sub = Bundle(path: path) {
                return sub
            }
        }
        return pkg
    }

    static func from(code: String?) -> AppLanguage {
        guard let code, let match = AppLanguage(rawValue: code) else {
            return .english
        }
        return match
    }
}

/// Lightweight global accessor used by non-View call sites (`L10n.*`,
/// model `label` getters) so they can pick the right localization without
/// every callsite having to read `AppState`. Updated by `AppState`
/// whenever the user changes the language.
///
/// `nonisolated(unsafe)` because the variable is only mutated from the
/// main actor (settings change) and read from arbitrary contexts that
/// build localized strings. A racing read returns either the old or
/// new locale, both valid; nothing relies on a stricter ordering.
enum AppLocale {
    /// Cached locale of the active language. Default seeded by
    /// `AppLanguage.bootstrap()` from persisted UserDefaults.
    nonisolated(unsafe) static var current: Locale = .init(identifier: "en")
    /// Sub-bundle of the active language. `String(localized:bundle:)`
    /// honors the locale chosen here regardless of the system locale,
    /// because the bundle itself only contains one language's strings.
    /// Initialised lazily on first read so it points at the package
    /// resource bundle, not at `Bundle.module`. See `packageBundle`.
    nonisolated(unsafe) static var bundle: Bundle = AppLocale.packageBundle

    /// The SwiftPM-emitted `Bundle.module` accessor looks for the
    /// resource bundle at `Bundle.main.bundleURL/<X>.bundle`, which
    /// resolves to the .app root on macOS even though resources actually
    /// live under `Contents/Resources/`. Reading `.module` from a
    /// shipped .app crashes on launch. Resolve the bundle ourselves
    /// from `resourceURL`, which is the canonical path on macOS, and
    /// fall back to `Bundle.main` so non-app callers (CLI tools, tests)
    /// stay usable.
    static let packageBundle: Bundle = {
        let bundleName = "Clawix_Clawix.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName)
        ]
        for url in candidates {
            if let url, let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle.main
    }()
}

extension AppLanguage {
    /// Persistence key (suite `appPrefsSuite`).
    static let storageKey = "PreferredLanguage"
    static let storage = UserDefaults(suiteName: appPrefsSuite) ?? .standard

    /// Read the saved language (or system default the first time the
    /// user runs the app).
    static func loadPersisted() -> AppLanguage {
        if let raw = storage.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        // First launch: pick whichever supported language matches the
        // system best. `Locale.preferredLanguages` is a list like
        // ["es-ES", "en-US"] — we walk it and stop at the first match.
        for pref in Locale.preferredLanguages {
            // Match exact tag first ("zh-Hans", "pt-BR"), then language.
            if let lang = AppLanguage(rawValue: pref) { return lang }
            let primary = pref.split(separator: "-").first.map(String.init) ?? pref
            if let lang = AppLanguage(rawValue: primary) { return lang }
        }
        return .english
    }

    /// Apply a language process-wide. Sets `AppleLanguages` (so any
    /// fresh `String(localized:bundle:)` lookup resolves against the
    /// xcstrings entry for this locale), seeds `AppLocale.current`, and
    /// persists the choice for the next launch.
    static func apply(_ lang: AppLanguage) {
        storage.set(lang.rawValue, forKey: storageKey)
        // Drives Foundation's lookup paths. Not load-bearing for our own
        // L10n helpers (those go through `AppLocale.bundle` directly)
        // but keeps `Locale.current` and any system framework that
        // sniffs `AppleLanguages` in sync with the user's choice.
        UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
        AppLocale.current = lang.locale
        AppLocale.bundle = lang.bundle
    }

    /// Called once from `ClawixApp.init` BEFORE any view renders, so the
    /// very first `String(localized:)` call already sees the right locale.
    static func bootstrap() {
        let lang = loadPersisted()
        apply(lang)
    }
}
