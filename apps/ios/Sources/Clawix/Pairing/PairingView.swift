import SwiftUI
import ClawixCore

// Phase 3 placeholder. Real QR scanning + Keychain persistence ship
// in Phase 6. For now the view explains the flow and offers a
// "continue with mock" action for the simulator.

struct PairingView: View {
    let onPaired: () -> Void

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                logoBlock
                instructions
                Spacer()
                continueMockButton
            }
            .padding(.horizontal, Layout.screenHorizontalPadding)
            .padding(.bottom, 32)
        }
    }

    private var logoBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.cardFill)
                    .frame(width: 64, height: 64)
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Palette.textPrimary)
            }
            Text("Pair with your Mac")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Scan the QR code Clawix shows on your Mac to link this iPhone over the local network.")
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: Layout.cardSpacing) {
            stepRow(index: "1", text: "Open Clawix on your Mac.")
            stepRow(index: "2", text: "Click the iPhone icon in the sidebar footer.")
            stepRow(index: "3", text: "Hold this iPhone in front of the QR code.")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .strokeBorder(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
        )
    }

    private func stepRow(index: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(index)
                .font(Typography.secondaryFont)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 14, alignment: .leading)
            Text(text)
                .font(Typography.bodyFont)
                .foregroundStyle(MenuStyle.rowText)
                .lineSpacing(2)
        }
    }

    private var continueMockButton: some View {
        Button(action: onPaired) {
            Text("Continue with mock data")
                .font(Typography.bodyEmphasized)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: Layout.buttonCornerRadius, style: .continuous)
                        .fill(Color(white: 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.buttonCornerRadius, style: .continuous)
                        .strokeBorder(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Pairing") {
    PairingView(onPaired: {})
        .preferredColorScheme(.dark)
}
