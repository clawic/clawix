import SwiftUI
#if canImport(UIKit)
import UIKit
import PhotosUI

// `PHPickerViewController` wrapped as a SwiftUI sheet. We use it for
// the full-library "Todas las fotos" entry point because it sandboxes
// the picker's access (no Photos permission prompt for the user even
// when the app has it denied) and gives Apple's familiar grid + albums
// UI for free.

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onPicked: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let owner: PhotoLibraryPicker

        init(_ owner: PhotoLibraryPicker) {
            self.owner = owner
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Empty results = user tapped Cancel. The owner's onCancel
            // handler also dismisses the sheet so the SwiftUI parent
            // can clear its presentation state.
            guard !results.isEmpty else {
                owner.onCancel()
                return
            }
            Task {
                let images = await Self.loadImages(from: results)
                await MainActor.run {
                    owner.onPicked(images)
                }
            }
        }

        private static func loadImages(from results: [PHPickerResult]) async -> [UIImage] {
            await withTaskGroup(of: (Int, UIImage?).self) { group in
                for (index, result) in results.enumerated() {
                    group.addTask {
                        let image = await loadImage(from: result.itemProvider)
                        return (index, image)
                    }
                }
                var ordered: [(Int, UIImage)] = []
                for await (index, image) in group {
                    if let image { ordered.append((index, image)) }
                }
                return ordered.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
        }

        private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
            await withCheckedContinuation { continuation in
                guard provider.canLoadObject(ofClass: UIImage.self) else {
                    continuation.resume(returning: nil)
                    return
                }
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
        }
    }
}
#endif
