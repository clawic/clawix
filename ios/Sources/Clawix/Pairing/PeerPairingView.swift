import SwiftUI
import AVFoundation

/// QR scanner specialised to consume `clawix://pair?v=1&d=…` links.
/// Sits alongside the existing `PairingView`/`QRScannerView` which are used
/// for pairing iOS with the macOS bridge; this view is for pairing two peers
/// at the Profile layer.
struct PeerPairingView: View {
    @ObservedObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var resolved: ProfileClient.Handle?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                QRScannerView(onResult: handleResult)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(16)
                if let handle = resolved {
                    pairedCard(handle: handle)
                } else if let error = error {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red.opacity(0.8))
                        .padding(.horizontal, 20).padding(.bottom, 16)
                } else {
                    Text("Point the camera at the peer's pairing QR.")
                        .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                        .padding(.bottom, 16)
                }
            }
            .background(Palette.background)
            .navigationTitle("Pair peer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func handleResult(_ payload: String) {
        Task {
            guard payload.hasPrefix("clawix://pair?") else {
                error = "Not a Clawix pairing link."
                return
            }
            if let handle = await store.pair(link: payload) {
                resolved = handle
                error = nil
            } else {
                error = "Could not resolve the handle."
            }
        }
    }

    private func pairedCard(handle: ProfileClient.Handle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("@\(handle.alias)").font(.system(size: 14, weight: .semibold)).kerning(-0.2)
            Text("." + handle.fingerprint).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardFill)
    }
}
