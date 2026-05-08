import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
import LucideIcon
#endif

// Bottom sheet shown when the composer's "+" button is tapped. The
// layout mirrors the screenshot the user provided: a header row with
// the app name on the left and a "Todas las fotos" link on the right,
// followed by a horizontal strip whose first tile opens the camera
// and whose remaining tiles are recent photos pulled from the library
// via PhotoKit. Each photo tile carries a selection ring that fills
// when tapped; the parent receives the chosen images via `onSelect`.

#if canImport(UIKit)
struct AttachmentSheetView: View {
    let onCamera: () -> Void
    let onAllPhotos: () -> Void
    let onSelect: ([UIImage]) -> Void
    let onDismiss: () -> Void

    @State private var loader = RecentPhotosLoader()
    @State private var selectedAssetIds: Set<String> = []
    @State private var inFlightConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            switch loader.authorization {
            case .authorized, .limited:
                strip
            case .denied:
                deniedState
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
            case .undetermined:
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
            }

            if !selectedAssetIds.isEmpty {
                confirmBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .background(Palette.surface.ignoresSafeArea())
        .task {
            await loader.start()
        }
        .animation(.easeInOut(duration: 0.18), value: selectedAssetIds.isEmpty)
    }

    private var header: some View {
        HStack {
            Text("Clawix")
                .font(BodyFont.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Button(action: {
                Haptics.tap()
                onAllPhotos()
            }) {
                Text("Todas las fotos")
                    .font(BodyFont.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(red: 0.27, green: 0.55, blue: 1.0))
            }
            .buttonStyle(.plain)
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                cameraTile
                ForEach(loader.assets, id: \.localIdentifier) { asset in
                    photoTile(asset: asset)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
        .frame(height: 168)
    }

    private var cameraTile: some View {
        Button(action: {
            Haptics.tap()
            onCamera()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.16))
                Image(lucide: .camera)
                    .font(BodyFont.system(size: 28, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .frame(width: 132, height: 160)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open camera")
    }

    private func photoTile(asset: PHAsset) -> some View {
        let isSelected = selectedAssetIds.contains(asset.localIdentifier)
        return Button(action: {
            toggle(asset: asset)
        }) {
            ZStack(alignment: .topTrailing) {
                if let preview = loader.thumbnails[asset.localIdentifier] {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 132, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(white: 0.18))
                        .frame(width: 132, height: 160)
                }
                selectionCircle(isSelected: isSelected)
                    .padding(8)
            }
            .frame(width: 132, height: 160)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func selectionCircle(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color(red: 0.27, green: 0.55, blue: 1.0) : Color.black.opacity(0.30))
                .frame(width: 26, height: 26)
            Circle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 26, height: 26)
            if isSelected {
                Image(lucide: .check)
                    .font(BodyFont.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
    }

    private var confirmBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Button(action: confirmSelection) {
                HStack(spacing: 8) {
                    if inFlightConfirm {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.black)
                    }
                    Text("Add \(selectedAssetIds.count)")
                        .font(BodyFont.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule(style: .continuous).fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(inFlightConfirm)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var deniedState: some View {
        VStack(spacing: 10) {
            Image(lucide: .images)
                .font(BodyFont.system(size: 32, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
            Text("Photo access disabled")
                .font(Typography.bodyEmphasized)
                .foregroundStyle(Palette.textPrimary)
            Text("Enable Photos in Settings to attach images, or open the system picker with \"Todas las fotos\" above.")
                .font(Typography.secondaryFont)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func toggle(asset: PHAsset) {
        Haptics.selection()
        if selectedAssetIds.contains(asset.localIdentifier) {
            selectedAssetIds.remove(asset.localIdentifier)
        } else {
            selectedAssetIds.insert(asset.localIdentifier)
        }
    }

    private func confirmSelection() {
        guard !inFlightConfirm else { return }
        inFlightConfirm = true
        let chosen = loader.assets.filter { selectedAssetIds.contains($0.localIdentifier) }
        Task {
            var images: [UIImage] = []
            for asset in chosen {
                if let image = await loader.loadFullImage(for: asset) {
                    images.append(image)
                }
            }
            await MainActor.run {
                inFlightConfirm = false
                onSelect(images)
            }
        }
    }
}
#endif
