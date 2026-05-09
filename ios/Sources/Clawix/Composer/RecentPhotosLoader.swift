import Foundation
#if canImport(UIKit)
import UIKit
import Photos

// Loads thumbnails of the most recent photos in the user's library for
// the horizontal strip in the attachment sheet. Authorization is
// never requested automatically: opening the attachment sheet should
// not trigger a privacy prompt. The full-library entry point uses
// PHPicker, which lets the user pick images without granting broad
// read access; the recent strip only appears after the app already
// has Photos access.
//
// Thumbnails are loaded on a background queue, decoded to a small
// in-memory size, and pushed to the main actor as they arrive. The
// loader is one-shot: SwiftUI re-creates it when the sheet opens, so
// we don't bother caching across presentations.

@Observable
final class RecentPhotosLoader {
    enum Authorization: Equatable {
        case undetermined
        case denied
        case limited
        case authorized
    }

    var authorization: Authorization = .undetermined
    var assets: [PHAsset] = []
    var thumbnails: [String: UIImage] = [:]

    private let imageManager = PHCachingImageManager()
    private let thumbnailSize = CGSize(width: 360, height: 360)

    /// Thumbnails arrive one-by-one from `PHCachingImageManager`. Each
    /// callback used to mutate `thumbnails` directly, which made
    /// `@Observable` notify the grid 60 times in a row when the sheet
    /// opens. We collect into `pendingThumbs` and drain into
    /// `thumbnails` on a 200ms debounce so the grid re-renders ~5×
    /// instead of 60×.
    @ObservationIgnored
    private var pendingThumbs: [String: UIImage] = [:]
    @ObservationIgnored
    private var thumbsFlushScheduled: Bool = false

    @MainActor
    func start() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized:
            authorization = .authorized
            await fetchRecent()
        case .limited:
            authorization = .limited
            await fetchRecent()
        case .denied, .restricted:
            authorization = .denied
        case .notDetermined:
            authorization = .undetermined
        @unknown default:
            authorization = .denied
        }
    }

    @MainActor
    private func fetchRecent() async {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.fetchLimit = 60
        let result = PHAsset.fetchAssets(with: options)
        var batch: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in batch.append(asset) }
        self.assets = batch
        for asset in batch {
            requestThumbnail(asset)
        }
    }

    private func requestThumbnail(_ asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let key = asset.localIdentifier
        imageManager.requestImage(
            for: asset,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let self, let image else { return }
            Task { @MainActor in
                self.pendingThumbs[key] = image
                self.scheduleThumbsFlush()
            }
        }
    }

    @MainActor
    private func scheduleThumbsFlush() {
        guard !thumbsFlushScheduled else { return }
        thumbsFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self?.flushPendingThumbs()
        }
    }

    @MainActor
    private func flushPendingThumbs() {
        thumbsFlushScheduled = false
        guard !pendingThumbs.isEmpty else { return }
        // One assignment per drain so `@Observable` notifies once
        // regardless of how many thumbnails landed in this window.
        var merged = thumbnails
        for (k, v) in pendingThumbs {
            merged[k] = v
        }
        pendingThumbs.removeAll(keepingCapacity: true)
        thumbnails = merged
    }

    /// Loads a full-resolution image for one asset, ready to attach.
    /// Returns nil if the asset is iCloud-only and the network fetch
    /// fails or the user denies download.
    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .none
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                continuation.resume(returning: image)
            }
        }
    }
}
#endif
