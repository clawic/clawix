import SwiftUI

/// Sheet shown when the user taps "Type a code instead" on the
/// pairing screen. Browses for `_clawix-bridge._tcp` Macs on the
/// local Wi-Fi, lets the user pick one if there is more than one,
/// and accepts the 9-character short code printed by `clawix pair`
/// on the Mac.
struct ShortCodePairingView: View {
    let onPaired: (Credentials) -> Void
    let onCancel: () -> Void

    @State private var flow = ShortCodePairingFlow()
    @State private var rawCode: String = ""
    @State private var pickedMacId: String?
    @State private var localError: String?
    @State private var isPairing: Bool = false

    private var formattedCode: String {
        let cleaned = rawCode.uppercased().filter { allowedAlphabet.contains($0) }
        let limited = String(cleaned.prefix(9))
        var out = ""
        for (idx, ch) in limited.enumerated() {
            if idx == 3 || idx == 6 { out.append("-") }
            out.append(ch)
        }
        return out
    }

    private var isCodeComplete: Bool {
        rawCode.uppercased().filter { allowedAlphabet.contains($0) }.count == 9
    }

    private var resolvedMac: ShortCodePairingFlow.DiscoveredMac? {
        if let pickedMacId, let m = flow.discovered.first(where: { $0.id == pickedMacId }) { return m }
        return flow.discovered.first
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                header
                discoveredBlock
                codeInput
                if let display = displayedError {
                    Text(display)
                        .font(Typography.captionFont)
                        .foregroundStyle(Color.red.opacity(0.85))
                }
                Spacer(minLength: 12)
                pairButton
            }
            .padding(.horizontal, AppLayout.screenHorizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .onAppear { flow.startBrowsing() }
        .onDisappear { flow.stopBrowsing() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Type your code")
                    .font(BodyFont.system(size: 26, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.textPrimary)
                Text("Run `clawix pair` on your Mac and read the 9-character code below the QR.")
                    .font(Typography.bodyFont)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
            }
            Spacer()
            Button(action: {
                Haptics.tap()
                onCancel()
            }) {
                LucideIcon(.x, size: 14)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .glassCircle()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var discoveredBlock: some View {
        if flow.discovered.isEmpty {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Looking for your Mac on this Wi-Fi…")
                    .font(Typography.captionFont)
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassRounded(radius: AppLayout.cardCornerRadius)
        } else if flow.discovered.count == 1, let mac = flow.discovered.first {
            HStack {
                LucideIcon(.laptop)
                    .foregroundStyle(Palette.textSecondary)
                Text(mac.name)
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                LucideIcon(.circleCheck)
                    .foregroundStyle(Color.green.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassRounded(radius: AppLayout.cardCornerRadius)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick the Mac to pair with:")
                    .font(Typography.captionFont)
                    .foregroundStyle(Palette.textTertiary)
                ForEach(flow.discovered) { mac in
                    Button(action: {
                        Haptics.tap()
                        pickedMacId = mac.id
                    }) {
                        HStack {
                            LucideIcon(.laptop)
                                .foregroundStyle(Palette.textSecondary)
                            Text(mac.name)
                                .font(Typography.bodyEmphasized)
                                .foregroundStyle(Palette.textPrimary)
                            Spacer()
                            if (pickedMacId ?? flow.discovered.first?.id) == mac.id {
                                LucideIcon(.circleCheck)
                                    .foregroundStyle(Color.green.opacity(0.85))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .glassRounded(radius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var codeInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code")
                .font(Typography.captionFont)
                .foregroundStyle(Palette.textTertiary)
            TextField("XXX-XXX-XXX", text: Binding(
                get: { formattedCode },
                set: { newValue in rawCode = newValue }
            ))
            .font(BodyFont.system(size: 22, weight: .semibold).monospaced())
            .tracking(2)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.go)
            .onSubmit { tryPair() }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassRounded(radius: AppLayout.cardCornerRadius)
        }
    }

    private var displayedError: String? {
        if let e = localError { return e }
        if case .error(let msg) = flow.status { return msg }
        return nil
    }

    private var pairButton: some View {
        Button(action: { tryPair() }) {
            ZStack {
                if isPairing {
                    ProgressView().tint(.black)
                } else {
                    Text("Pair")
                        .font(Typography.bodyEmphasized)
                        .foregroundStyle(Color.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(canSubmit ? Color.white : Color.white.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var canSubmit: Bool {
        isCodeComplete && resolvedMac != nil && !isPairing
    }

    private func tryPair() {
        guard let mac = resolvedMac else {
            localError = "No Macs found on this Wi-Fi yet. Make sure `clawix start` is running."
            return
        }
        guard isCodeComplete else {
            localError = "The code is 9 characters."
            return
        }
        localError = nil
        isPairing = true
        Haptics.send()
        Task {
            do {
                let creds = try await flow.pair(with: mac, code: formattedCode)
                CredentialStore.shared.save(creds)
                Haptics.success()
                onPaired(creds)
            } catch {
                isPairing = false
                if localError == nil {
                    localError = error.localizedDescription
                }
            }
        }
    }
}

private let allowedAlphabet: Set<Character> = Set("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
