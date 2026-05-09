import SwiftUI

struct ProviderStatusPill: View {
    enum Status {
        case configured(count: Int)
        case empty
        case disabled
    }

    let status: Status

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(fill)
        )
    }

    private var label: String {
        switch status {
        case .configured(let count):
            return count == 1 ? "1 account" : "\(count) accounts"
        case .empty: return "No accounts"
        case .disabled: return "Disabled"
        }
    }

    private var dotColor: Color {
        switch status {
        case .configured: return Color.green
        case .empty: return Color(white: 0.5)
        case .disabled: return Color(red: 0.85, green: 0.35, blue: 0.35)
        }
    }

    private var textColor: Color {
        switch status {
        case .configured: return Palette.textPrimary
        case .empty, .disabled: return Palette.textSecondary
        }
    }

    private var fill: Color {
        switch status {
        case .configured: return Color.green.opacity(0.10)
        case .empty: return Color.white.opacity(0.04)
        case .disabled: return Color.red.opacity(0.10)
        }
    }
}
