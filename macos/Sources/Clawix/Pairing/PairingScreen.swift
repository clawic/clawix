import SwiftUI

/// Pair with a peer by exchanging an opaque pairing payload or scanning a QR.
/// The macOS surface focuses on:
///   - Generating my own pairing link / QR (server-side; this view just shows
///     what the daemon already produced).
///   - Pasting a peer's link and resolving the handle.
struct PairingScreen: View {
    @ObservedObject var manager: ProfileManager
    @State private var pastedLink: String = ""
    @State private var resolved: ClawJSProfileClient.Handle?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            header
            HStack(alignment: .top, spacing: 24) {
                myCard.frame(maxWidth: .infinity)
                peerCard.frame(maxWidth: .infinity)
            }
            Spacer()
        }
        .padding(24)
        .background(Color.black)
    }

    private var header: some View {
        HStack {
            Text("Pair with a peer").font(.system(size: 18, weight: .semibold)).kerning(-0.4)
            Spacer()
        }
    }

    private var myCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your handle").font(.system(size: 12, weight: .semibold)).kerning(-0.2)
                .foregroundStyle(Palette.textSecondary)
            if let me = manager.me {
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(me.handle.alias)").font(.system(size: 16, weight: .semibold)).kerning(-0.2)
                    Text("." + me.handle.fingerprint).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary).textSelection(.enabled)
                }
                placeholderQr(text: me.handle.fingerprint)
            } else {
                Text("Initialise your profile first.").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var peerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Peer pairing payload").font(.system(size: 12, weight: .semibold)).kerning(-0.2)
                .foregroundStyle(Palette.textSecondary)
            TextEditor(text: $pastedLink)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 80)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            HStack {
                Button("Resolve and add") {
                    Task {
                        do {
                            let handle = try await manager.pair(link: pastedLink)
                            resolved = handle
                            error = nil
                        } catch let err {
                            error = err.localizedDescription
                            resolved = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pastedLink.isEmpty)
                Spacer()
            }
            if let r = resolved {
                resolvedRow(handle: r)
            }
            if let e = error {
                Text(e).font(.system(size: 12)).foregroundStyle(Color.red.opacity(0.8))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func resolvedRow(handle: ClawJSProfileClient.Handle) -> some View {
        HStack(spacing: 8) {
            LucideIcon(.check, size: 13).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(handle.alias)").font(.system(size: 13, weight: .medium)).kerning(-0.2)
                Text("." + handle.fingerprint).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func placeholderQr(text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
            VStack(spacing: 6) {
                LucideIcon(.scan, size: 30)
                Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(width: 180, height: 180)
    }
}
