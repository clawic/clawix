import SwiftUI

/// Module-internal `Color(hex:)` shared by every Apps surface
/// (sidebar row, home grid card, settings page row). Lives in its own
/// file so the surface views can each declare their helpers without
/// conflicting `init(hex:)` extensions on `Color`.
extension Color {
    init?(appsHex hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
