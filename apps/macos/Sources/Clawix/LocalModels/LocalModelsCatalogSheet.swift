import SwiftUI
import LucideIcon

/// Modal browser over the curated catalog. The user picks a model and a
/// variant (size); we hand the choice back via the closure and the
/// caller (`LocalModelsPage`) kicks off the pull through `LocalModelsService`.
///
/// Branding: every visible string here comes from `LocalModelsCatalog`,
/// which never mentions the upstream runtime. Provider is the model
/// author (Meta, Mistral, …), and download size labels read directly
/// from the catalog entry.
struct LocalModelsCatalogSheet: View {

    let installedModelNames: Set<String>
    let onPick: (String) -> Void
    let onClose: () -> Void

    @State private var selectedVariantTag: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.07))
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14),
                              GridItem(.flexible(), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(LocalModelsCatalog.entries) { entry in
                        card(for: entry)
                    }
                }
                .padding(20)
            }
            .thinScrollers()
            .background(Palette.background)
        }
        .frame(width: 720, height: 560)
        .background(Palette.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browse models")
                    .font(BodyFont.system(size: 16, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text("Pick a model to download. All run on this Mac.")
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Image(lucide: .x)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.textSecondary)
                    .padding(8)
                    .background(
                        Circle().fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Palette.background)
    }

    // MARK: - Card

    private func card(for entry: LocalModelsCatalog.Entry) -> some View {
        let pickedTag = selectedVariantTag[entry.id] ?? entry.defaultVariant.tag
        let pickedVariant = entry.variants.first(where: { $0.tag == pickedTag }) ?? entry.defaultVariant
        let pullName = LocalModelsCatalog.pullName(entry, variant: pickedVariant)
        let alreadyInstalled = installedModelNames.contains(pullName)

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(BodyFont.system(size: 13.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(entry.provider)
                    .font(BodyFont.system(size: 10.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }

            Text(entry.description)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            capabilityBadges(entry.capabilities)

            if entry.variants.count > 1 {
                HStack(spacing: 6) {
                    ForEach(entry.variants, id: \.tag) { variant in
                        variantChip(variant: variant, isSelected: variant.tag == pickedTag) {
                            selectedVariantTag[entry.id] = variant.tag
                        }
                    }
                }
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(pickedVariant.sizeLabel)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text("\(pickedVariant.recommendedRAMGB) GB RAM recommended")
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                if alreadyInstalled {
                    Text("Installed")
                        .font(BodyFont.system(size: 10.5, wght: 700))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                } else {
                    Button {
                        onPick(pullName)
                    } label: {
                        Text("Download")
                            .font(BodyFont.system(size: 11, wght: 600))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color(white: 0.15))
                            )
                            .foregroundColor(Palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.085))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
        )
    }

    private func capabilityBadges(_ caps: Set<LocalModelsCatalog.Capability>) -> some View {
        HStack(spacing: 4) {
            ForEach(LocalModelsCatalog.Capability.allCases.filter(caps.contains), id: \.self) { cap in
                Text(cap.label)
                    .font(BodyFont.system(size: 9.5, wght: 700))
                    .foregroundColor(Palette.textPrimary.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
        }
    }

    private func variantChip(
        variant: LocalModelsCatalog.Variant,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(variant.tag.uppercased())
                .font(BodyFont.system(size: 10, wght: 700))
                .foregroundColor(isSelected ? .black : Palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}
