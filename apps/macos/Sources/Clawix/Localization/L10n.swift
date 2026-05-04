import Foundation
import SwiftUI

// Centralised localisation helpers. The bulk of the strings live in
// `Resources/Localizable.xcstrings` (source language: English) and are
// resolved automatically by SwiftUI when a literal is passed to `Text`,
// `Button`, `accessibilityLabel`, etc. This file covers the cases where
// SwiftUI's automatic lookup is not enough:
//
//   • Properties that return `String` (intelligence/speed/permission
//     labels, status text, default fallbacks). `Text(stringVar)` does
//     NOT localise, so the property itself must return an already
//     localised value.
//   • Strings with run-time interpolation that need plural support.
//   • Helper funcs to keep the call sites tidy.
//
// All keys use the English source as their literal, matching the
// xcstrings sourceLanguage. The compiled per-locale `.strings` /
// `.stringsdict` files (emitted by `scripts/compile_xcstrings.py`) use
// those same English keys, so a lookup hits regardless of the active
// language.
//
// Every helper passes `locale: AppLocale.current` so the lookup honors
// the user-selected language (set from Settings → General → Idioma)
// even when Foundation's per-bundle preferredLocalizations cache hasn't
// refreshed yet.

enum L10n {

    // MARK: - Plain lookups (already localised String)

    /// Convenience around `String(localized:bundle:locale:)` that reads
    /// from the package's bundle and the user-chosen locale. Use for
    /// fixed labels stored in model types so `Text(label)` renders the
    /// localised value.
    static func t(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    // MARK: - Plurals

    static func exploredFiles(_ count: Int) -> String {
        String(localized: "Explored \(count) files", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func ranCommands(_ count: Int) -> String {
        String(localized: "Ran \(count) commands", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    /// Inline tool-group label fragment. Clawix shows the lowercase
    /// "ran N command(s)" idiom embedded inside a comma-joined
    /// work-summary line. The L10n value keeps that exact phrasing so
    /// hydrated history matches Clawix.
    static func ranCommandsInline(_ count: Int) -> String {
        String(localized: "ran \(count) commands", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    /// Inline tool-group label fragment for parsed list_files actions.
    /// Clawix shows just the count with no leading verb, so we mirror
    /// that to keep the comma-joined row readable.
    static func listedItems(_ count: Int) -> String {
        String(localized: "\(count) lists", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    /// Link rendered above the visible chat slice when older messages
    /// are collapsed.
    static func previousMessages(_ count: Int) -> String {
        String(localized: "\(count) previous messages", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func modifiedFiles(_ count: Int) -> String {
        String(localized: "Modified \(count) files", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func generatedImages(_ count: Int) -> String {
        String(localized: "Generated \(count) images", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func viewedImages(_ count: Int) -> String {
        String(localized: "Viewed \(count) images", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func installedPlugins(_ count: Int) -> String {
        String(localized: "\(count) plugins installed", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    // MARK: - Relative dates (used by sidebar chat rows)

    /// Shorthand label used next to chat titles. Bucket boundaries
    /// are kept in sync with `RecentChatRow.relative(from:)`.
    static func relativeAge(elapsed: TimeInterval) -> String {
        if elapsed < 60 {
            return String(localized: "now", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if elapsed < 3_600 {
            return String(localized: "\(Int(elapsed / 60)) min", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if elapsed < 86_400 {
            return String(localized: "\(Int(elapsed / 3_600)) h", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if elapsed < 604_800 {
            return String(localized: "\(Int(elapsed / 86_400)) d", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if elapsed < 2_629_800 {
            return String(localized: "\(Int(elapsed / 604_800)) w", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        return String(localized: "\(Int(elapsed / 2_629_800)) mo", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    // MARK: - Work summary header

    static func workingFor(seconds: Int) -> String {
        String(localized: "Working \(seconds) s", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func workedFor(seconds: Int) -> String {
        String(localized: "Worked for \(seconds) s", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func usedTool(_ name: String) -> String {
        String(localized: "Used \(name)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    // MARK: - Search

    static func noSearchResults(query: String) -> String {
        String(localized: "No results for «\(query)»", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    // MARK: - Home heading

    /// Heading shown above the composer on the home screen. When a
    /// project is selected the project name is interpolated; otherwise
    /// a generic "what should we build" prompt is used.
    static func homeHeading(project: String?) -> String {
        if let project, !project.isEmpty {
            return String(localized: "What should we work on in \(project)?", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        return String(localized: "What should we build?", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    // MARK: - Accessibility

    static func a11yChangePermissions(label: String) -> String {
        String(localized: "Change permissions: \(label)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func a11yModelPicker(model: String, intelligence: String) -> String {
        String(localized: "Model picker: GPT-\(model) \(intelligence)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func a11yYou(_ content: String) -> String {
        String(localized: "You: \(content)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func a11yAssistant(_ content: String) -> String {
        String(localized: "Assistant: \(content)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func a11yPluginToggle(name: String, isOn: Bool) -> String {
        if isOn {
            return String(localized: "\(name) on", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        return String(localized: "\(name) off", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    // MARK: - Settings / status

    static func defaultModelLabel(_ model: String) -> String {
        String(localized: "Default model: \(model)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func errorPrefix(_ message: String) -> String {
        String(localized: "Error: \(message)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func signInFailed(_ message: String) -> String {
        String(localized: "Could not sign in: \(message)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func runtimeIndexReadFailed(_ message: String) -> String {
        String(localized: "Could not read the runtime index: \(message)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func chatsAutoGroupedByPath(_ count: Int) -> String {
        String(localized: "\(count) chats auto-grouped by path", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    static func accountLabel(_ name: String) -> String {
        String(localized: "Account \(name)", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    // MARK: - Help menu

    static func sendFeedbackToApple(appName: String) -> String {
        String(localized: "Send feedback about \(appName) to Apple", bundle: AppLocale.bundle, locale: AppLocale.current)
    }
}

// `IntelligenceLevel.label`, `SpeedLevel.label` and `PermissionMode.label`
// in AppState already return localised values via String(localized:).
// They double as keys in the catalog and as display strings.
