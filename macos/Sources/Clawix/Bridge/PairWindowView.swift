import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit
import ClawixEngine

private let daemonBridgePort: UInt16 = 24080

struct PairWindowView: View {
    @State private var payload: String = ""
    @State private var host: String = "..."
    @State private var token: String = ""
    @StateObject private var backgroundBridge: BackgroundBridgeService = .shared

    private var pairing: PairingService {
        if backgroundBridge.isActive {
            return PairingService(defaults: UserDefaults(suiteName: ClawixPersistentSurfaceKeys.bridgeDefaultsSuite) ?? .standard,
                                  port: daemonBridgePort)
        }
        return PairingService.shared
    }

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            Text("Pair iPhone")
                .font(BodyFont.system(size: 16, wght: 700))
                .foregroundStyle(Color.white.opacity(0.94))
            Text("Open Clawix on your iPhone and scan this code while both devices are on the same WiFi.")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            qrImage
                .frame(width: 240, height: 240)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                )

            VStack(spacing: 6) {
                row(label: "Host", value: host)
                row(label: "Port", value: "\(pairing.port)")
                row(label: "Token", value: tokenPreview)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )

            HStack(spacing: 10) {
                Button(action: rotate) {
                    Text("Rotate token")
                        .font(BodyFont.system(size: 12, wght: 500))
                }
                .buttonStyle(.borderless)
                Button(action: copyPayload) {
                    Text("Copy payload")
                        .font(BodyFont.system(size: 12, wght: 500))
                }
                .buttonStyle(.borderless)
            }
            .foregroundStyle(Color.white.opacity(0.55))
            Spacer()
        }
        .padding(28)
        .frame(width: 360, height: 540)
        .background(Color(white: 0.06).ignoresSafeArea())
        .onAppear(perform: refresh)
    }

    private var tokenPreview: String {
        guard token.count > 12 else { return token }
        return token.prefix(8) + "…" + token.suffix(4)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(BodyFont.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private func refresh() {
        backgroundBridge.refresh()
        token = pairing.bearer
        payload = pairing.qrPayload()
        host = PairingService.currentLANIPv4() ?? "no LAN"
    }

    private func rotate() {
        pairing.rotateBearer()
        refresh()
    }

    private func copyPayload() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(payload, forType: .string)
    }

    @ViewBuilder
    private var qrImage: some View {
        if let nsImage = Self.makeQR(from: payload) {
            Image(nsImage: nsImage)
                .interpolation(.none)
                .resizable()
        } else {
            LucideIcon(.squareDashed, size: 168)
                .foregroundStyle(Color.black.opacity(0.4))
        }
    }

    static func makeQR(from string: String) -> NSImage? {
        guard !string.isEmpty, let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = CGAffineTransform(scaleX: 12, y: 12)
        let scaled = output.transformed(by: scale)
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
