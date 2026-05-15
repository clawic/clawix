import AIProviders
import SwiftUI

/// Squircle background filled with the provider's brand color, with
/// the monogram overlaid in white. v1 ships these as monograms instead
/// of remote SVGs to avoid bundling third-party logos.
struct ProviderBrandIcon: View {
    let brand: ProviderBrand
    var size: CGFloat = 28

    var body: some View {
        let color = Color(hex: brand.colorHex) ?? Color(white: 0.3)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.9))
            Text(brand.monogram)
                .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

extension Color {
    init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
