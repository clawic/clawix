import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Centralized haptic feedback. Every tap that should feel "physical"
// goes through here so we can later gate the whole system on a user
// preference without having to chase scattered `UIImpactFeedback`
// calls. Feel guidelines:
//
//   - `.tap`         — light tick for routine taps (chat row, project
//                       row, navigation buttons, sheet open / dismiss).
//   - `.selection`   — segment / picker / toggle changes where the
//                       feedback should read as "I picked something".
//   - `.send`        — medium impact for the dominant action of a
//                       screen (sending a prompt, FAB launching a new
//                       chat).
//   - `.success`     — notification feedback for completed operations
//                       the user is waiting on (QR pairing scanned,
//                       copy-to-clipboard confirmed).
//   - `.warning`     — notification feedback for destructive choices
//                       (unpair, disconnect).
//
// Generators are recreated per call. UIKit pools them internally, so
// the cost is negligible compared to the cleanliness of not having
// to manage prepared() lifecycles all over the view hierarchy.

enum Haptics {
    static func tap() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    static func selection() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    static func send() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
}
