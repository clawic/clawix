import SwiftUI
#if canImport(UIKit)
import UIKit
import AVFoundation
import LucideIcon

// Full-screen camera with the three bottom controls from the brief:
//   - photo library shortcut on the left
//   - large white capture button in the middle
//   - flip-camera button on the right
// We run our own `AVCaptureSession` instead of falling back to
// `UIImagePickerController` so the chrome matches the rest of the
// app and so the bottom controls can be the exact ones in the spec
// (the system picker draws its own and they collide visually).

struct CameraCaptureView: View {
    let onCaptured: (UIImage) -> Void
    let onOpenLibrary: () -> Void
    let onCancel: () -> Void

    @State private var coordinator = CameraCoordinator()
    @State private var torchOn: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            CameraPreview(coordinator: coordinator)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                controls
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            coordinator.start()
        }
        .onDisappear {
            coordinator.stop()
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: {
                Haptics.tap()
                onCancel()
            }) {
                Image(lucide: .x)
                    .font(BodyFont.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: toggleTorch) {
                Image(lucideOrSystem: torchOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(BodyFont.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var controls: some View {
        HStack(alignment: .center) {
            Button(action: {
                Haptics.tap()
                onOpenLibrary()
            }) {
                Image(lucide: .images)
                    .font(BodyFont.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open photo library")

            Spacer()

            Button(action: capture) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Capture photo")

            Spacer()

            Button(action: {
                Haptics.selection()
                coordinator.flip()
            }) {
                Image(lucide: .refresh_cw)
                    .font(BodyFont.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Flip camera")
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 36)
    }

    private func capture() {
        Haptics.send()
        coordinator.capture { image in
            guard let image else { return }
            DispatchQueue.main.async {
                onCaptured(image)
            }
        }
    }

    private func toggleTorch() {
        torchOn.toggle()
        coordinator.setTorch(torchOn)
        Haptics.tap()
    }
}

// MARK: - AVFoundation glue

@MainActor
@Observable
final class CameraCoordinator {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "clawix.camera.session", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var currentPosition: AVCaptureDevice.Position = .back
    private var capturedHandler: ((UIImage?) -> Void)?
    private var photoDelegate: PhotoDelegate?

    func start() {
        queue.async { [self] in
            if session.inputs.isEmpty {
                configure()
            }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func flip() {
        currentPosition = (currentPosition == .back) ? .front : .back
        queue.async { [self] in
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            attachInput(position: currentPosition)
            session.commitConfiguration()
        }
    }

    func setTorch(_ on: Bool) {
        queue.async { [self] in
            guard let device = AVCaptureDevice.default(for: .video),
                  device.hasTorch
            else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {
                // Best-effort: torch failure shouldn't break capture.
            }
        }
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        queue.async { [self] in
            let settings = AVCapturePhotoSettings()
            let delegate = PhotoDelegate { [weak self] image in
                self?.photoDelegate = nil
                completion(image)
            }
            self.photoDelegate = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        attachInput(position: currentPosition)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
    }

    private func attachInput(position: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
        else { return }
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else {
            completion(nil)
            return
        }
        completion(image)
    }
}

// MARK: - Preview layer

private struct CameraPreview: UIViewRepresentable {
    let coordinator: CameraCoordinator

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = coordinator.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
#endif
