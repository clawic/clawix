import SwiftUI
import AVFoundation
import AppKit

/// In-line camera sheet that replaces the previous Photo Booth fallback.
/// Presents a webcam preview, a circular shutter button, and a cancel
/// affordance. On capture, encodes the still as PNG to a tmp URL under
/// `~/Library/Caches/Clawix-Captures/` and hands it to the caller as an
/// attachment URL. Dismissal without capture leaves no side effect.
struct QuickAskCameraSheet: View {
    @Binding var isPresented: Bool
    /// Called once with the on-disk URL of the captured PNG. Not called
    /// if the user cancels.
    var onCapture: (URL) -> Void

    @StateObject private var session = QuickAskCameraSession()
    @State private var capturing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let error = errorMessage {
                    VStack(spacing: 6) {
                        LucideIcon(.triangleAlert, size: 15.5)
                            .foregroundColor(.yellow)
                        Text(error)
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    QuickAskCameraPreviewLayer(session: session)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(width: 420, height: 315)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(action: snap) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                            .frame(width: 48, height: 48)
                        Circle()
                            .fill(capturing ? Color.white.opacity(0.5) : Color.white)
                            .frame(width: 38, height: 38)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(capturing || errorMessage != nil)
                .keyboardShortcut(.return, modifiers: [])

                Spacer()

                Color.clear.frame(width: 60)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .background(Color(white: 0.08))
        .onAppear { session.start { errorMessage = $0 } }
        .onDisappear { session.stop() }
    }

    private func snap() {
        capturing = true
        session.capturePNG { url in
            capturing = false
            guard let url else { return }
            onCapture(url)
            isPresented = false
        }
    }
}

private struct QuickAskCameraPreviewLayer: NSViewRepresentable {
    let session: QuickAskCameraSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        let preview = AVCaptureVideoPreviewLayer(session: session.captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer?.addSublayer(preview)
        context.coordinator.preview = preview
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.preview?.frame = nsView.bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var preview: AVCaptureVideoPreviewLayer?
    }
}

@MainActor
final class QuickAskCameraSession: ObservableObject {
    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureDelegate: PhotoCaptureDelegate?

    func start(onError: @escaping (String) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configure(onError: onError)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configure(onError: onError)
                    } else {
                        onError("Camera access denied. Enable Clawix in System Settings → Privacy → Camera.")
                    }
                }
            }
        default:
            onError("Camera access denied. Enable Clawix in System Settings → Privacy → Camera.")
        }
    }

    func stop() {
        if captureSession.isRunning { captureSession.stopRunning() }
    }

    func capturePNG(completion: @escaping (URL?) -> Void) {
        let settings = AVCapturePhotoSettings()
        let delegate = PhotoCaptureDelegate { [weak self] url in
            self?.captureDelegate = nil
            completion(url)
        }
        captureDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private func configure(onError: @escaping (String) -> Void) {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard let device = AVCaptureDevice.default(for: .video) else {
            onError("No camera device found.")
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            onError("Could not initialise camera input: \(error.localizedDescription)")
            return
        }
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.startRunning()
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        DispatchQueue.main.async { [completion] in
            guard error == nil,
                  let data = photo.fileDataRepresentation(),
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:])
            else {
                completion(nil)
                return
            }
            let dir = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Clawix-Captures", isDirectory: true)
            guard let dir else {
                completion(nil)
                return
            }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            let url = dir.appendingPathComponent("camera-\(stamp).png")
            do {
                try png.write(to: url)
                completion(url)
            } catch {
                completion(nil)
            }
        }
    }
}
