import SwiftUI

/// Scenes tab. Activate-only surface in Phase 3; scene authoring lands
/// in the Phase 4 editor.
struct IoTScenesView: View {
    @EnvironmentObject private var manager: IoTManager
    @State private var activatingId: String?

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)],
                spacing: 12,
            ) {
                ForEach(manager.scenes) { scene in
                    SceneCard(
                        scene: scene,
                        isActivating: activatingId == scene.id,
                        onActivate: { Task { await activate(scene) } },
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)

            if manager.scenes.isEmpty {
                Text(verbatim: "No scenes yet.")
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(Palette.textTertiary)
                    .padding(.top, 80)
            }
        }
        .thinScrollers()
    }

    private func activate(_ scene: SceneRecord) async {
        activatingId = scene.id
        defer { activatingId = nil }
        try? await manager.activateScene(scene)
    }
}

private struct SceneCard: View {
    let scene: SceneRecord
    let isActivating: Bool
    var onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 32, height: 32)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Palette.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: scene.label)
                        .font(BodyFont.system(size: 13, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    if let description = scene.description, !description.isEmpty {
                        Text(verbatim: description)
                            .font(BodyFont.system(size: 10))
                            .foregroundColor(Palette.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }

            Text(verbatim: "\(scene.actions.count) action\(scene.actions.count == 1 ? "" : "s")")
                .font(BodyFont.system(size: 10))
                .foregroundColor(Palette.textTertiary)

            HStack {
                Spacer()
                Button(action: onActivate) {
                    HStack(spacing: 5) {
                        if isActivating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                                .tint(Palette.textPrimary)
                        }
                        Text(verbatim: isActivating ? "Activating…" : "Activate")
                            .font(BodyFont.system(size: 11, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isActivating)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}
