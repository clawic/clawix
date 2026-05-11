import SwiftUI
import AppKit

struct AndroidSimulatorFrameSurface: View {
    let image: NSImage
    let aspectRatio: CGFloat
    let stageSize: CGSize
    let onPointer: (AndroidSimulatorPointerPhase, CGPoint) -> Void

    var body: some View {
        let screenRect = displayRect(in: stageSize)
        let chromeRect = screenRect.insetBy(dx: -11, dy: -11)
        let radius = min(34, max(16, min(chromeRect.width, chromeRect.height) * 0.08))

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(white: 0.025))
                .frame(width: chromeRect.width, height: chromeRect.height)
                .position(x: chromeRect.midX, y: chromeRect.midY)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 0.9)
                        .frame(width: chromeRect.width, height: chromeRect.height)
                        .position(x: chromeRect.midX, y: chromeRect.midY)
                )
                .shadow(color: .black.opacity(0.48), radius: 18, x: 0, y: 12)

            AndroidSimulatorFramebufferView(image: image, onPointer: onPointer)
                .frame(width: screenRect.width, height: screenRect.height)
                .position(x: screenRect.midX, y: screenRect.midY)
        }
        .frame(width: stageSize.width, height: stageSize.height)
    }

    private func displayRect(in size: CGSize) -> CGRect {
        let maxWidth = max(120, size.width - 50)
        let maxHeight = max(160, size.height - 50)
        var width = min(maxWidth, maxHeight * aspectRatio)
        var height = width / aspectRatio
        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}

struct AndroidSimulatorFramebufferView: NSViewRepresentable {
    let image: NSImage
    let onPointer: (AndroidSimulatorPointerPhase, CGPoint) -> Void

    func makeNSView(context: Context) -> FramebufferNSView {
        FramebufferNSView(image: image, onPointer: onPointer)
    }

    func updateNSView(_ nsView: FramebufferNSView, context: Context) {
        nsView.image = image
        nsView.imageSize = image.size
        nsView.onPointer = onPointer
        nsView.needsDisplay = true
    }

    final class FramebufferNSView: NSView {
        var image: NSImage
        var imageSize: CGSize
        var onPointer: (AndroidSimulatorPointerPhase, CGPoint) -> Void

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        init(image: NSImage, onPointer: @escaping (AndroidSimulatorPointerPhase, CGPoint) -> Void) {
            self.image = image
            self.imageSize = image.size
            self.onPointer = onPointer
            super.init(frame: .zero)
            wantsLayer = true
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Embedded Android emulator framebuffer")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            NSGraphicsContext.current?.imageInterpolation = .medium
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onPointer(.began, mapToDevice(event))
        }

        override func mouseDragged(with event: NSEvent) {
            onPointer(.moved, mapToDevice(event))
        }

        override func mouseUp(with event: NSEvent) {
            onPointer(.ended, mapToDevice(event))
        }

        override func accessibilityPerformPress() -> Bool {
            guard let point = currentMousePoint() else { return false }
            onPointer(.began, point)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.onPointer(.ended, point)
            }
            return true
        }

        private func mapToDevice(_ event: NSEvent) -> CGPoint {
            let local = convert(event.locationInWindow, from: nil)
            return mapLocalPointToDevice(local)
        }

        private func currentMousePoint() -> CGPoint? {
            guard let window else { return nil }
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            return mapLocalPointToDevice(convert(windowPoint, from: nil))
        }

        private func mapLocalPointToDevice(_ local: CGPoint) -> CGPoint {
            let clampedX = min(max(local.x, bounds.minX), bounds.maxX)
            let clampedY = min(max(local.y, bounds.minY), bounds.maxY)
            let x = (clampedX - bounds.minX) / max(1, bounds.width) * imageSize.width
            let y = (clampedY - bounds.minY) / max(1, bounds.height) * imageSize.height
            return CGPoint(x: x, y: y)
        }
    }
}

enum AndroidSimulatorPointerPhase {
    case began
    case moved
    case ended
}
