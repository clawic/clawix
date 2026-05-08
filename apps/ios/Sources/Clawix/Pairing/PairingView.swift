import SwiftUI
import ClawixCore

// First-run pairing screen. Pure black canvas, with a glass-bordered
// instructions card and a glass capsule CTA. Stays consistent with
// the ChatGPT-style chrome the rest of the app uses.

struct PairingView: View {
    let onPaired: (Credentials) -> Void

    @State private var showScanner = false
    @State private var showShortCode = false
    @State private var lastError: String?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                qrHero
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 24)
                instructions
                if let lastError {
                    Text(lastError)
                        .font(Typography.captionFont)
                        .foregroundStyle(Color.red.opacity(0.85))
                        .padding(.top, 12)
                }
                Spacer(minLength: 24)
                scanButton
                shortCodeButton
                    .padding(.top, 12)
            }
            .padding(.horizontal, AppLayout.screenHorizontalPadding)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showScanner) {
            ScannerSheet(
                onScan: handleScan,
                onCancel: { showScanner = false },
                onError: { msg in
                    lastError = msg
                    showScanner = false
                }
            )
        }
        .sheet(isPresented: $showShortCode) {
            ShortCodePairingView(
                onPaired: { creds in
                    showShortCode = false
                    onPaired(creds)
                },
                onCancel: { showShortCode = false }
            )
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pair with your Mac")
                .font(BodyFont.system(size: 30, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
            Text("Open Clawix on your Mac, choose Window > Pair iPhone, and scan the QR with this device.")
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
        }
    }

    // Oversized QR mark sitting directly on the black canvas: no glass
    // bubble, no chrome. Each data module pulses on its own diagonal phase
    // so the matrix reads as a wave sweeping across, while the three
    // finder corners breathe gently to keep the icon feeling alive.
    private var qrHero: some View {
        AnimatedQRIcon(size: 156)
            .foregroundStyle(Palette.textPrimary)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: AppLayout.cardSpacing) {
            stepRow(index: "1", text: "Open Clawix on your Mac.")
            stepRow(index: "2", text: "Window menu > Pair iPhone (Cmd+Shift+P).")
            stepRow(index: "3", text: "Hold this iPhone in front of the QR code.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .glassRounded(radius: AppLayout.cardCornerRadius)
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

    private var scanButton: some View {
        Button(action: {
            Haptics.send()
            showScanner = true
        }) {
            Text("Scan QR")
                .font(Typography.bodyEmphasized)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule(style: .continuous).fill(Color.white)
                )
        }
        .buttonStyle(.plain)
    }

    private var shortCodeButton: some View {
        Button(action: {
            Haptics.tap()
            lastError = nil
            showShortCode = true
        }) {
            Text("Type a code instead")
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func handleScan(_ raw: String) {
        showScanner = false
        guard let payload = PairingPayload.parse(raw) else {
            lastError = "Not a Clawix pairing code"
            return
        }
        guard payload.v == 1 else {
            lastError = "Pairing format v\(payload.v) not supported. Update this app."
            return
        }
        let creds = payload.asCredentials
        CredentialStore.shared.save(creds)
        onPaired(creds)
    }
}

private struct ScannerSheet: View {
    let onScan: (String) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            QRScannerView(onScan: onScan, onError: onError)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Button(action: {
                        Haptics.tap()
                        onCancel()
                    }) {
                        LucideIcon(.x, size: 16)
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .glassCircle()
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    Spacer()
                }
                Spacer()
                Text("Scan the Clawix QR shown on your Mac")
                    .font(BodyFont.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCapsule()
                    .padding(.bottom, 40)
            }
        }
    }
}

#Preview("Pairing") {
    PairingView(onPaired: { _ in })
        .preferredColorScheme(.dark)
}
