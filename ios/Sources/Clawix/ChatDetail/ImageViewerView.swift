import SwiftUI

#if canImport(UIKit)
import UIKit
import Photos

// Fullscreen viewer for chat attachments. Mirrors the iOS Photos
// interaction set the user already has muscle memory for: pinch to
// zoom, double-tap to toggle 1x ↔ 2.5x, pan when zoomed, drag
// downward at base zoom to dismiss with the backdrop fading along
// the gesture. Multiple images on the same turn become horizontally
// pageable via the standard page-style TabView so swiping between
// photos feels native, with a subtle dot indicator only when there
// is more than one.
//
// Presented from `ChatDetailView` via `.fullScreenCover`. The
// receiver owns its own dismiss animation through `@Environment(\.dismiss)`
// so the cover can fade out cleanly without the parent having to
// drive a timed sheet binding.
struct ImageViewerView: View {
    let images: [UIImage]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss

    @State private var index: Int = 0
    @State private var backdropProgress: CGFloat = 0
    @State private var shareItem: ShareItem?
    @State private var toast: String?

    private var currentImage: UIImage? {
        guard images.indices.contains(index) else { return nil }
        return images[index]
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - 0.55 * Double(min(backdropProgress, 1)))
                .ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(images.indices, id: \.self) { i in
                    ZoomablePhoto(
                        image: images[i],
                        backdropProgress: $backdropProgress,
                        onDismiss: { dismiss() }
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))

            VStack {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Spacer()
                        GlassIconButton(
                            systemName: "arrow.down.to.line",
                            tint: Color.black.opacity(0.35)
                        ) {
                            if let img = currentImage { saveToPhotos(img) }
                        }
                        GlassIconButton(
                            systemName: "square.and.arrow.up",
                            tint: Color.black.opacity(0.35)
                        ) {
                            if let img = currentImage {
                                shareItem = ShareItem(image: img)
                            }
                        }
                        GlassIconButton(
                            systemName: "xmark",
                            tint: Color.black.opacity(0.35)
                        ) { dismiss() }
                    }
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
                Spacer()
            }
            .opacity(1 - Double(min(backdropProgress, 1)))

            if let toast {
                VStack {
                    Spacer()
                    SaveToastPill(text: toast)
                        .padding(.bottom, 48)
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden(true)
        .onAppear {
            index = max(0, min(startIndex, images.count - 1))
            Haptics.tap()
        }
        .sheet(item: $shareItem) { item in
            ImageShareSheet(items: [item.image])
        }
    }

    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    showToast("Photo access denied")
                    return
                }
                PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.creationRequestForAsset(from: image)
                } completionHandler: { success, _ in
                    DispatchQueue.main.async {
                        if success {
                            Haptics.success()
                            showToast("Saved to Photos")
                        } else {
                            showToast("Couldn't save")
                        }
                    }
                }
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.22)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.22)) { toast = nil }
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ImageShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

private struct SaveToastPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: Capsule(style: .continuous))
    }
}

// Single zoomable photo page. State (scale, offset) is local so each
// page in the TabView remembers its own zoom while the user swipes
// between attachments. When the photo is at base zoom, vertical
// drags become a pull-to-dismiss gesture that drives
// `backdropProgress` so the parent can fade out the surround in
// sync with the finger; releasing past the threshold tears the
// viewer down. When zoomed in, horizontal/vertical drags pan the
// image instead and the dismiss path is suppressed so the user can
// inspect detail without accidentally closing.
private struct ZoomablePhoto: View {
    let image: UIImage
    @Binding var backdropProgress: CGFloat
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var pullOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 6.0
    private let dismissDistance: CGFloat = 140
    private let dismissVelocity: CGFloat = 240

    private var isZoomed: Bool { scale > 1.02 }

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(
                    x: offset.width + pullOffset.width,
                    y: offset.height + pullOffset.height
                )
                .gesture(SimultaneousGesture(magnify, drag))
                .onTapGesture(count: 2) { handleDoubleTap() }
        }
        .contentShape(Rectangle())
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let target = lastScale * value.magnification
                scale = min(max(target, minScale * 0.85), maxScale)
            }
            .onEnded { _ in
                if scale < minScale {
                    withAnimation(.easeOut(duration: 0.18)) {
                        scale = minScale
                        offset = .zero
                    }
                }
                lastScale = scale
                lastOffset = offset
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                if isZoomed {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                } else if value.translation.height > 0 &&
                          abs(value.translation.height) > abs(value.translation.width) {
                    pullOffset = CGSize(width: value.translation.width * 0.4,
                                        height: value.translation.height)
                    backdropProgress = max(0, value.translation.height / 320)
                }
            }
            .onEnded { value in
                if isZoomed {
                    lastOffset = offset
                    return
                }
                let translatedFar = value.translation.height > dismissDistance
                let flickedDown = value.predictedEndTranslation.height > dismissVelocity &&
                                  value.translation.height > 30
                if translatedFar || flickedDown {
                    Haptics.tap()
                    onDismiss()
                } else {
                    withAnimation(.easeOut(duration: 0.22)) {
                        pullOffset = .zero
                        backdropProgress = 0
                    }
                }
            }
    }

    private func handleDoubleTap() {
        Haptics.tap()
        withAnimation(.easeInOut(duration: 0.22)) {
            if isZoomed {
                scale = minScale
                lastScale = minScale
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }
}

#endif
