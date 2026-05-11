import SwiftUI

/// Compact card for an entity in the Catalog grid. Adapts its layout by
/// type kind (media / text / data) but keeps a consistent footprint
/// so the grid feels uniform across types. Text on photos uses a
/// bottom gradient, never an opaque pill (taste rule #5).
struct IndexEntityCard: View {
    let entity: ClawJSIndexClient.Entity
    let onSelect: () -> Void

    private var meta: IndexTypeMeta { IndexTypeCatalog.meta(for: entity.typeName) }
    private var title: String { entity.title ?? entityFallbackTitle(entity) }
    private var subtitle: String? { entitySubtitle(entity) }

    private var thumbURL: URL? {
        guard let raw = entity.thumbnailUrl, let url = URL(string: raw) else { return nil }
        return url
    }

    private var priceLabel: String? {
        if let price = entity.data["price"]?.asNumber {
            let currency = entity.data["currency"]?.asString ?? ""
            return formatPrice(price, currency: currency)
        }
        return nil
    }

    private var ratingLabel: String? {
        if let rating = entity.data["rating"]?.asNumber {
            return String(format: "%.1f", rating)
        }
        return nil
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 0) {
                    thumbnailArea
                        .frame(height: meta.kind == .media ? 140 : 86)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(lucideOrSystem: meta.lucideName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(meta.accent)
                            Text(meta.typeName.capitalized)
                                .font(BodyFont.system(size: 10.5, wght: 500))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Text(title)
                            .font(BodyFont.system(size: 13, wght: 600))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(BodyFont.system(size: 11, wght: 400))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }

    @ViewBuilder
    private var thumbnailArea: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = thumbURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        meta.accent.opacity(0.20)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        meta.accent.opacity(0.20)
                    @unknown default:
                        meta.accent.opacity(0.20)
                    }
                }
            } else {
                LinearGradient(
                    colors: [meta.accent.opacity(0.32), meta.accent.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(lucideOrSystem: meta.lucideName)
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(.white.opacity(0.6))
                )
            }

            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(spacing: 6) {
                if let priceLabel = priceLabel {
                    Text(priceLabel)
                        .font(BodyFont.system(size: 11.5, wght: 700))
                        .foregroundColor(.white)
                }
                if let ratingLabel = ratingLabel {
                    HStack(spacing: 3) {
                        Image(lucideOrSystem: "star")
                            .font(.system(size: 9, weight: .semibold))
                        Text(ratingLabel)
                            .font(BodyFont.system(size: 11.5, wght: 600))
                    }
                    .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
    }
}

private func entityFallbackTitle(_ entity: ClawJSIndexClient.Entity) -> String {
    if let name = entity.data["name"]?.asString { return name }
    if let title = entity.data["title"]?.asString { return title }
    if let url = entity.sourceUrl { return url }
    return entity.identityKey
}

private func entitySubtitle(_ entity: ClawJSIndexClient.Entity) -> String? {
    switch entity.typeName {
    case "product":
        if let vendor = entity.data["vendor"]?.asString { return vendor }
        return entity.data["brand"]?.asString
    case "listing":
        return entity.data["location"]?.asObject?["city"]?.asString
    case "article":
        return entity.data["publication"]?.asString ?? entity.data["author_name"]?.asString
    case "post":
        return entity.data["author_handle"]?.asString ?? entity.data["platform"]?.asString
    case "video":
        return entity.data["channel_name"]?.asString
    case "episode":
        return entity.data["podcast_name"]?.asString
    case "paper":
        return entity.data["venue"]?.asString
    case "profile":
        return entity.data["bio"]?.asString
    case "place":
        return entity.data["address"]?.asString
    case "channel":
        return entity.data["subtype"]?.asString
    case "doc":
        return entity.data["site"]?.asString
    case "repo":
        return "\(entity.data["owner"]?.asString ?? "")/\(entity.data["name"]?.asString ?? "")"
    case "event":
        return entity.data["starts_at"]?.asString
    case "job":
        return entity.data["company_name"]?.asString
    case "review":
        return entity.data["author_name"]?.asString
    default:
        return entity.sourceUrl
    }
}

private func formatPrice(_ value: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 2
    let n = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    if currency.isEmpty { return n }
    if currency.count <= 3 { return "\(n) \(currency)" }
    return "\(n) \(currency)"
}
