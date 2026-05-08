import SwiftUI
import AppKit

struct ImagePreviewOverlay: View {
    @ObservedObject var appState: AppState

    @State private var nsImage: NSImage?
    @State private var scale: CGFloat = 0.5
    @State private var lastScale: CGFloat = 0.5
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var appeared: Bool = false

    private let initialScale: CGFloat = 0.5
    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 8.0
    private let scaleStep: CGFloat = 0.125

    var body: some View {
        ZStack {
            if let url = appState.imagePreviewURL {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                if let image = nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let next = lastScale * value
                                    scale = clamp(next)
                                }
                                .onEnded { _ in
                                    if scale <= initialScale + 0.0001 {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            offset = .zero
                                        }
                                    }
                                    lastScale = scale
                                    lastOffset = offset
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1.0 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeOut(duration: 0.20)) {
                                if scale > initialScale + 0.0001 {
                                    scale = initialScale
                                    offset = .zero
                                } else {
                                    scale = 1.0
                                }
                                lastScale = scale
                                lastOffset = offset
                            }
                        }
                        .padding(40)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.96)
                }

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Button(action: { downloadImage(from: url) }) {
                                roundIconLabel(systemName: "arrow.down.to.line")
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t("Download image"))

                            Button(action: dismiss) {
                                roundIconLabel(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)
                        }
                        .padding(.trailing, 18)
                        .padding(.top, 18)
                    }
                    Spacer()

                    if nsImage != nil {
                        ZoomControl(
                            percent: Int(round(scale / initialScale * 100)),
                            canDecrease: scale > minScale + 0.0001,
                            canIncrease: scale < maxScale - 0.0001,
                            onDecrease: { stepZoom(-scaleStep) },
                            onIncrease: { stepZoom(scaleStep) }
                        )
                        .padding(.bottom, 26)
                        .opacity(appeared ? 1 : 0)
                    }
                }
            }
        }
        .onChange(of: appState.imagePreviewURL) { _, newValue in
            if let url = newValue {
                load(url: url)
            } else {
                reset()
            }
        }
        .onAppear {
            if let url = appState.imagePreviewURL { load(url: url) }
        }
        .background(
            EscKeyCatcher(active: appState.imagePreviewURL != nil) {
                dismiss()
            }
        )
    }

    private func roundIconLabel(systemName: String) -> some View {
        LucideIcon.auto(systemName, size: 13)
            .foregroundColor(Color(white: 0.94))
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(0.12)))
            .contentShape(Circle())
    }

    private func clamp(_ s: CGFloat) -> CGFloat {
        min(max(s, minScale), maxScale)
    }

    private func stepZoom(_ delta: CGFloat) {
        withAnimation(.easeOut(duration: 0.16)) {
            let next = clamp(scale + delta)
            scale = next
            lastScale = next
            if next <= 1.0 + 0.0001 {
                offset = .zero
                lastOffset = .zero
            }
        }
    }

    private func load(url: URL) {
        nsImage = NSImage(contentsOf: url)
        scale = initialScale
        lastScale = initialScale
        offset = .zero
        lastOffset = .zero
        appeared = false
        withAnimation(.easeOut(duration: 0.18)) {
            appeared = true
        }
    }

    private func reset() {
        nsImage = nil
        scale = initialScale
        lastScale = initialScale
        offset = .zero
        lastOffset = .zero
        appeared = false
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.16)) {
            appState.imagePreviewURL = nil
        }
    }

    private func downloadImage(from url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                NSLog("ImagePreviewOverlay: download failed: \(error)")
            }
        }
    }
}

private struct ZoomControl: View {
    let percent: Int
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ZoomCircleButton(systemName: "minus", enabled: canDecrease, action: onDecrease)
                .padding(.leading, 6)

            Text("\(percent)%")
                .font(BodyFont.system(size: 14, wght: 600))
                .foregroundColor(Color(white: 0.94))
                .monospacedDigit()
                .frame(minWidth: 64)
                .padding(.horizontal, 4)

            ZoomCircleButton(systemName: "plus", enabled: canIncrease, action: onIncrease)
                .padding(.trailing, 6)
        }
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(white: 0.18).opacity(0.96))
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.40), radius: 18, x: 0, y: 10)
    }
}

private struct ZoomCircleButton: View {
    let systemName: String
    let enabled: Bool
    let action: () -> Void

    @State private var hovering: Bool = false

    var body: some View {
        Button(action: action) {
            LucideIcon.auto(systemName, size: 12)
                .foregroundColor(Color(white: enabled ? 0.94 : 0.5))
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(Color.white.opacity(hovering && enabled ? 0.14 : 0.09))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = enabled && $0 }
    }
}

private struct EscKeyCatcher: NSViewRepresentable {
    let active: Bool
    let onEsc: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onEsc = onEsc
        return v
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onEsc = onEsc
        nsView.active = active
        if active {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }

    final class CatcherView: NSView {
        var onEsc: (() -> Void)?
        var active: Bool = false
        override var acceptsFirstResponder: Bool { active }
        override func keyDown(with event: NSEvent) {
            if active && event.keyCode == 53 {
                onEsc?()
                return
            }
            super.keyDown(with: event)
        }
    }
}
