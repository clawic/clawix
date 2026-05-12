import SwiftUI

/// Right pane that shows the selected entity. Header (thumbnail +
/// title + meta) + per-type tab strip + tab content. One file owns all
/// 15 canonical type renderings via a switch to keep the surface compact
/// and avoid drift between sibling detail views.
struct EntityDetailPane: View {
    @ObservedObject var manager: IndexManager
    let entityId: String?

    @State private var detail: ClawJSIndexClient.EntityDetailResponse?
    @State private var loadError: String?
    @State private var activeTab: DetailTab = .overview
    @State private var historyByField: [String: [ClawJSIndexClient.HistoryPoint]] = [:]

    enum DetailTab: Hashable {
        case overview
        case timeseries(field: String)
        case observations
        case relations
        case raw
    }

    var body: some View {
        Group {
            if let entityId {
                content(for: entityId)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .task(id: entityId) {
            await load()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            IndexIcon(size: 36).foregroundColor(.white.opacity(0.25))
            Text("Select an entity")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(.white.opacity(0.45))
            Text("Tap any card on the left to inspect it here.")
                .font(BodyFont.system(size: 11, wght: 400))
                .foregroundColor(.white.opacity(0.30))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for entityId: String) -> some View {
        if let error = loadError {
            IndexEmptyState(
                title: "Could not load entity",
                systemImage: "exclamationmark.circle",
                description: error
            )
        } else if let detail = detail {
            VStack(spacing: 0) {
                DetailHeader(detail: detail)
                CardDivider()
                DetailTabStrip(detail: detail, activeTab: $activeTab)
                CardDivider()
                ScrollView {
                    detailBody(for: detail)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .thinScrollers()
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func detailBody(for detail: ClawJSIndexClient.EntityDetailResponse) -> some View {
        switch activeTab {
        case .overview:
            EntityOverviewSection(detail: detail)
        case .timeseries(let field):
            TimeseriesSection(
                entityId: detail.entity.id,
                field: field,
                points: historyByField[field] ?? [],
                onLoad: { await loadHistory(field) }
            )
        case .observations:
            ObservationsSection(observations: detail.observations)
        case .relations:
            RelationsSection(detail: detail)
        case .raw:
            RawJSONSection(entity: detail.entity)
        }
    }

    private func load() async {
        guard let entityId else { return }
        detail = nil
        loadError = nil
        do {
            detail = try await manager.detail(for: entityId)
            historyByField = [:]
            activeTab = .overview
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadHistory(_ field: String) async {
        guard let entityId else { return }
        if historyByField[field] != nil { return }
        do {
            let points = try await manager.history(for: entityId, field: field)
            historyByField[field] = points
        } catch {
            historyByField[field] = []
        }
    }
}

private struct DetailHeader: View {
    let detail: ClawJSIndexClient.EntityDetailResponse

    private var meta: IndexTypeMeta { IndexTypeCatalog.meta(for: detail.entity.typeName) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    LucideIcon.auto(meta.lucideName, size: 11)
                        .foregroundColor(meta.accent)
                    Text(meta.displayName)
                        .font(BodyFont.system(size: 10.5, wght: 600))
                        .foregroundColor(.white.opacity(0.55))
                        .textCase(.uppercase)
                }
                Text(detail.entity.title ?? detail.entity.identityKey)
                    .font(BodyFont.system(size: 16, wght: 700))
                    .foregroundColor(.white)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    if let url = detail.entity.sourceUrl {
                        Text(URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url)
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Text("Last seen \(relativeTime(detail.entity.lastSeenAt))")
                        .font(BodyFont.system(size: 11, wght: 400))
                        .foregroundColor(.white.opacity(0.40))
                }
                if !detail.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(detail.tags) { tag in
                            TagBadge(tag: tag)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let size: CGFloat = 56
        ZStack {
            if let raw = detail.entity.thumbnailUrl, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: meta.accent.opacity(0.25)
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: meta.accent.opacity(0.25)
                    @unknown default: meta.accent.opacity(0.25)
                    }
                }
            } else {
                LinearGradient(
                    colors: [meta.accent.opacity(0.45), meta.accent.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    LucideIcon.auto(meta.lucideName, size: 22)
                        .foregroundColor(.white.opacity(0.85))
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TagBadge: View {
    let tag: ClawJSIndexClient.EntityTag
    var body: some View {
        Text(tag.name)
            .font(BodyFont.system(size: 10.5, wght: 600))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
    }
}

private struct DetailTabStrip: View {
    let detail: ClawJSIndexClient.EntityDetailResponse
    @Binding var activeTab: EntityDetailPane.DetailTab

    private var tabs: [(EntityDetailPane.DetailTab, String)] {
        var result: [(EntityDetailPane.DetailTab, String)] = [(.overview, "Overview")]
        let timeseriesFields = timeseriesFieldsForType(detail.entity.typeName)
        for field in timeseriesFields {
            if detail.entity.data[field] != nil {
                result.append((.timeseries(field: field), prettyFieldName(field)))
            }
        }
        result.append((.observations, "Observations (\(detail.observations.count))"))
        let relations = detail.relationsFrom.count + detail.relationsTo.count
        if relations > 0 {
            result.append((.relations, "Relations (\(relations))"))
        }
        result.append((.raw, "Raw"))
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { _, entry in
                    let (tab, title) = entry
                    Button { activeTab = tab } label: {
                        Text(title)
                            .font(BodyFont.system(size: 11.5, wght: tab == activeTab ? 600 : 500))
                            .foregroundColor(tab == activeTab ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(tab == activeTab ? Color.white.opacity(0.10) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct EntityOverviewSection: View {
    let detail: ClawJSIndexClient.EntityDetailResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch detail.entity.typeName {
            case "product":
                ProductOverview(entity: detail.entity)
            case "listing":
                ListingOverview(entity: detail.entity)
            case "article":
                ArticleOverview(entity: detail.entity)
            case "post":
                PostOverview(entity: detail.entity)
            case "video":
                VideoOverview(entity: detail.entity)
            case "episode":
                EpisodeOverview(entity: detail.entity)
            case "paper":
                PaperOverview(entity: detail.entity)
            case "profile":
                ProfileOverview(entity: detail.entity)
            case "place":
                PlaceOverview(entity: detail.entity)
            case "channel":
                ChannelOverview(entity: detail.entity)
            case "doc":
                DocOverview(entity: detail.entity)
            case "repo":
                RepoOverview(entity: detail.entity)
            case "event":
                EventOverview(entity: detail.entity)
            case "job":
                JobOverview(entity: detail.entity)
            case "review":
                ReviewOverview(entity: detail.entity)
            default:
                GenericOverview(entity: detail.entity)
            }
            if let url = detail.entity.sourceUrl, let parsed = URL(string: url) {
                OpenSourceUrlRow(url: parsed)
            }
        }
    }
}

private struct ObservationsSection: View {
    let observations: [ClawJSIndexClient.Observation]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(observations) { observation in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(relativeTime(observation.observedAt))
                            .font(BodyFont.system(size: 12, wght: 600))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        if !observation.changedFields.isEmpty {
                            Text(observation.changedFields.joined(separator: ", "))
                                .font(BodyFont.system(size: 10.5, wght: 500))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    if let url = observation.sourceUrl {
                        Text(URL(string: url)?.host ?? url)
                            .font(BodyFont.system(size: 10.5, wght: 400))
                            .foregroundColor(.white.opacity(0.40))
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
            if observations.isEmpty {
                Text("No observations yet.")
                    .font(BodyFont.system(size: 12, wght: 400))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }
}

private struct RelationsSection: View {
    let detail: ClawJSIndexClient.EntityDetailResponse
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !detail.relationsFrom.isEmpty {
                Text("This entity is linked to")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(.white.opacity(0.55))
                ForEach(detail.relationsFrom) { rel in
                    Text("→ \(rel.relationType) → \(rel.toEntityId)")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            if !detail.relationsTo.isEmpty {
                Text("Pointed at by")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(.white.opacity(0.55))
                ForEach(detail.relationsTo) { rel in
                    Text("← \(rel.relationType) ← \(rel.fromEntityId)")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }
}

private struct RawJSONSection: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        let json = (try? JSONSerialization.data(
            withJSONObject: ["id": entity.id, "type": entity.typeName, "data": entity.data.mapValues { $0.swiftValue }],
            options: [.prettyPrinted, .sortedKeys]
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "(failed to serialize)"
        return Text(json)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.85))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.30))
            )
    }
}

private struct TimeseriesSection: View {
    let entityId: String
    let field: String
    let points: [ClawJSIndexClient.HistoryPoint]
    let onLoad: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prettyFieldName(field))
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(.white)
            TimeseriesChart(points: points)
                .frame(height: 160)
            if points.isEmpty {
                Text("No history yet for this field. Run the Search again or wait for the next Monitor fire.")
                    .font(BodyFont.system(size: 11, wght: 400))
                    .foregroundColor(.white.opacity(0.50))
            }
        }
        .task(id: field) { await onLoad() }
    }
}

private struct OpenSourceUrlRow: View {
    let url: URL
    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                LucideIcon.auto("arrow.up.right.square", size: 11)
                Text("Open source")
                    .font(BodyFont.system(size: 12, wght: 500))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

// MARK: - Per-type overview sections

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(BodyFont.system(size: 10, wght: 600))
                .kerning(0.4)
                .foregroundColor(.white.opacity(0.45))
            Text(value)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DescriptionBlock: View {
    let text: String
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 12.5, wght: 400))
            .foregroundColor(.white.opacity(0.78))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProductOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                if let price = entity.data["price"]?.asNumber {
                    InfoRow(label: "Price", value: "\(price) \(entity.data["currency"]?.asString ?? "")")
                }
                if let stock = entity.data["stock"]?.asString { InfoRow(label: "Stock", value: stock) }
                if let rating = entity.data["rating"]?.asNumber {
                    InfoRow(label: "Rating", value: String(format: "%.1f", rating))
                }
            }
            if let brand = entity.data["brand"]?.asString { InfoRow(label: "Brand", value: brand) }
            if let vendor = entity.data["vendor"]?.asString { InfoRow(label: "Vendor", value: vendor) }
            if let description = entity.data["description"]?.asString { DescriptionBlock(text: description) }
        }
    }
}

private struct ListingOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let perNight = entity.data["price_per_night"]?.asNumber {
                    InfoRow(label: "Per night", value: "\(perNight) \(entity.data["currency"]?.asString ?? "")")
                } else if let price = entity.data["price"]?.asNumber {
                    InfoRow(label: "Price", value: "\(price) \(entity.data["currency"]?.asString ?? "")")
                }
                if let rating = entity.data["rating"]?.asNumber {
                    InfoRow(label: "Rating", value: String(format: "%.1f", rating))
                }
                if let availability = entity.data["availability"]?.asString {
                    InfoRow(label: "Availability", value: availability)
                }
            }
            if let location = entity.data["location"]?.asObject {
                let city = location["city"]?.asString
                let country = location["country"]?.asString
                if city != nil || country != nil {
                    InfoRow(label: "Location", value: [city, country].compactMap { $0 }.joined(separator: ", "))
                }
            }
            if let amenities = entity.data["amenities"]?.asArray, !amenities.isEmpty {
                let names = amenities.compactMap { $0.asString }
                InfoRow(label: "Amenities", value: names.joined(separator: " · "))
            }
            if let description = entity.data["description"]?.asString {
                DescriptionBlock(text: description)
            }
        }
    }
}

private struct ArticleOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let publication = entity.data["publication"]?.asString {
                InfoRow(label: "Publication", value: publication)
            }
            if let author = entity.data["author_name"]?.asString {
                InfoRow(label: "Author", value: author)
            }
            if let published = entity.data["published_at"]?.asString {
                InfoRow(label: "Published", value: published)
            }
            if let summary = entity.data["summary"]?.asString {
                DescriptionBlock(text: summary)
            } else if let text = entity.data["content_text"]?.asString {
                DescriptionBlock(text: text.prefix(800).description)
            }
            if let topics = entity.data["topics"]?.asArray, !topics.isEmpty {
                let names = topics.compactMap { $0.asString }
                InfoRow(label: "Topics", value: names.joined(separator: ", "))
            }
        }
    }
}

private struct PostOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let handle = entity.data["author_handle"]?.asString {
                InfoRow(label: "Author", value: "@\(handle)")
            }
            if let platform = entity.data["platform"]?.asString {
                InfoRow(label: "Platform", value: platform.capitalized)
            }
            if let body = entity.data["content_text"]?.asString {
                DescriptionBlock(text: body)
            }
            HStack(spacing: 14) {
                if let likes = entity.data["likes"]?.asNumber { Metric(label: "Likes", value: likes) }
                if let replies = entity.data["replies"]?.asNumber { Metric(label: "Replies", value: replies) }
                if let reposts = entity.data["reposts"]?.asNumber { Metric(label: "Reposts", value: reposts) }
                if let views = entity.data["views"]?.asNumber { Metric(label: "Views", value: views) }
            }
        }
    }
}

private struct Metric: View {
    let label: String
    let value: Double
    var body: some View {
        VStack(spacing: 2) {
            Text(formatCount(value))
                .font(BodyFont.system(size: 13, wght: 700))
                .foregroundColor(.white)
            Text(label.uppercased())
                .font(BodyFont.system(size: 9.5, wght: 600))
                .kerning(0.3)
                .foregroundColor(.white.opacity(0.45))
        }
    }
}

private struct VideoOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let channel = entity.data["channel_name"]?.asString {
                InfoRow(label: "Channel", value: channel)
            }
            if let duration = entity.data["duration_s"]?.asNumber {
                InfoRow(label: "Duration", value: formatDuration(Int(duration)))
            }
            if let views = entity.data["views"]?.asNumber {
                InfoRow(label: "Views", value: formatCount(views))
            }
            if let description = entity.data["description"]?.asString {
                DescriptionBlock(text: description)
            }
        }
    }
}

private struct EpisodeOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let podcast = entity.data["podcast_name"]?.asString {
                InfoRow(label: "Podcast", value: podcast)
            }
            if let duration = entity.data["duration_s"]?.asNumber {
                InfoRow(label: "Duration", value: formatDuration(Int(duration)))
            }
            if let published = entity.data["published_at"]?.asString {
                InfoRow(label: "Published", value: published)
            }
            if let notes = entity.data["show_notes"]?.asString {
                DescriptionBlock(text: notes)
            }
        }
    }
}

private struct PaperOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let authors = entity.data["authors"]?.asArray {
                let names = authors.compactMap { $0.asString }
                InfoRow(label: "Authors", value: names.joined(separator: ", "))
            }
            if let venue = entity.data["venue"]?.asString {
                InfoRow(label: "Venue", value: venue)
            }
            if let citations = entity.data["citations"]?.asNumber {
                InfoRow(label: "Citations", value: formatCount(citations))
            }
            if let abstract = entity.data["abstract"]?.asString {
                DescriptionBlock(text: abstract)
            }
        }
    }
}

private struct ProfileOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let bio = entity.data["bio"]?.asString {
                DescriptionBlock(text: bio)
            }
            HStack(spacing: 14) {
                if let followers = entity.data["followers"]?.asNumber { Metric(label: "Followers", value: followers) }
                if let following = entity.data["following"]?.asNumber { Metric(label: "Following", value: following) }
                if let posts = entity.data["post_count"]?.asNumber { Metric(label: "Posts", value: posts) }
            }
            if let platform = entity.data["platform"]?.asString {
                InfoRow(label: "Platform", value: platform.capitalized)
            }
        }
    }
}

private struct PlaceOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let address = entity.data["address"]?.asString {
                InfoRow(label: "Address", value: address)
            }
            HStack(spacing: 14) {
                if let rating = entity.data["rating"]?.asNumber {
                    Metric(label: "Rating", value: rating)
                }
                if let count = entity.data["review_count"]?.asNumber {
                    Metric(label: "Reviews", value: count)
                }
                if let priceLevel = entity.data["price_level"]?.asNumber {
                    Metric(label: "Price", value: priceLevel)
                }
            }
            if let cuisine = entity.data["cuisine"]?.asString {
                InfoRow(label: "Cuisine", value: cuisine)
            }
        }
    }
}

private struct ChannelOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let description = entity.data["description"]?.asString {
                DescriptionBlock(text: description)
            }
            HStack(spacing: 14) {
                if let subs = entity.data["subscribers"]?.asNumber {
                    Metric(label: "Subscribers", value: subs)
                }
                if let freq = entity.data["post_frequency"]?.asNumber {
                    Metric(label: "Per week", value: freq)
                }
            }
            if let language = entity.data["language"]?.asString {
                InfoRow(label: "Language", value: language)
            }
        }
    }
}

private struct DocOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let breadcrumbs = entity.data["breadcrumbs"]?.asArray {
                let names = breadcrumbs.compactMap { $0.asString }
                InfoRow(label: "Section", value: names.joined(separator: " / "))
            }
            if let modified = entity.data["last_modified_at"]?.asString {
                InfoRow(label: "Last modified", value: modified)
            }
            if let text = entity.data["content_text"]?.asString {
                DescriptionBlock(text: text.prefix(1000).description)
            }
        }
    }
}

private struct RepoOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let description = entity.data["description"]?.asString {
                DescriptionBlock(text: description)
            }
            HStack(spacing: 14) {
                if let stars = entity.data["stars"]?.asNumber {
                    Metric(label: "Stars", value: stars)
                }
                if let forks = entity.data["forks"]?.asNumber {
                    Metric(label: "Forks", value: forks)
                }
                if let issues = entity.data["open_issues"]?.asNumber {
                    Metric(label: "Issues", value: issues)
                }
            }
            if let lang = entity.data["primary_language"]?.asString {
                InfoRow(label: "Language", value: lang)
            }
            if let license = entity.data["license"]?.asString {
                InfoRow(label: "License", value: license)
            }
        }
    }
}

private struct EventOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let starts = entity.data["starts_at"]?.asString {
                InfoRow(label: "Starts", value: starts)
            }
            if let ends = entity.data["ends_at"]?.asString {
                InfoRow(label: "Ends", value: ends)
            }
            if let venue = entity.data["location"]?.asString {
                InfoRow(label: "Venue", value: venue)
            }
            HStack(spacing: 14) {
                if let priceMin = entity.data["price_min"]?.asNumber {
                    Metric(label: "Min price", value: priceMin)
                }
                if let priceMax = entity.data["price_max"]?.asNumber {
                    Metric(label: "Max price", value: priceMax)
                }
                if let left = entity.data["tickets_left"]?.asNumber {
                    Metric(label: "Tickets left", value: left)
                }
            }
            if let description = entity.data["description"]?.asString {
                DescriptionBlock(text: description)
            }
        }
    }
}

private struct JobOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let company = entity.data["company_name"]?.asString {
                InfoRow(label: "Company", value: company)
            }
            if let location = entity.data["location"]?.asString {
                InfoRow(label: "Location", value: location)
            }
            if let remote = entity.data["remote_policy"]?.asString {
                InfoRow(label: "Remote", value: remote)
            }
            HStack(spacing: 14) {
                if let min = entity.data["salary_min"]?.asNumber {
                    Metric(label: "Min", value: min)
                }
                if let max = entity.data["salary_max"]?.asNumber {
                    Metric(label: "Max", value: max)
                }
            }
            if let description = entity.data["description"]?.asString {
                DescriptionBlock(text: description)
            }
        }
    }
}

private struct ReviewOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let rating = entity.data["rating"]?.asNumber {
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { idx in
                        LucideIcon.auto("star", size: 14)
                            .foregroundColor(Double(idx) < rating ? Color.orange : Color.white.opacity(0.15))
                    }
                    Text(String(format: "%.1f", rating))
                        .font(BodyFont.system(size: 13, wght: 700))
                        .foregroundColor(.white)
                }
            }
            if let title = entity.data["title"]?.asString {
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(.white)
            }
            if let text = entity.data["content_text"]?.asString {
                DescriptionBlock(text: text)
            }
            if let author = entity.data["author_name"]?.asString {
                InfoRow(label: "Author", value: author)
            }
        }
    }
}

private struct GenericOverview: View {
    let entity: ClawJSIndexClient.Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(entity.data.keys.sorted()), id: \.self) { key in
                let value = entity.data[key]
                InfoRow(label: key, value: previewString(value))
            }
        }
    }
}

private func previewString(_ value: AnyJSON?) -> String {
    guard let value else { return "" }
    switch value {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .number(let n): return String(n)
    case .string(let s): return s
    case .array(let entries):
        return "[\(entries.count) items]"
    case .object:
        return "{…}"
    }
}

private func timeseriesFieldsForType(_ typeName: String) -> [String] {
    switch typeName {
    case "product": return ["price", "stock", "rating", "review_count", "position_in_search"]
    case "listing": return ["price", "price_per_night", "availability", "rating", "review_count"]
    case "article": return ["view_count"]
    case "post":    return ["likes", "replies", "reposts", "views", "bookmarks"]
    case "video":   return ["views", "likes", "comment_count"]
    case "episode": return ["downloads", "rating"]
    case "paper":   return ["citations", "downloads"]
    case "profile": return ["followers", "following", "post_count"]
    case "place":   return ["rating", "review_count", "price_level"]
    case "channel": return ["subscribers", "post_frequency"]
    case "doc":     return ["last_modified_at"]
    case "repo":    return ["stars", "forks", "open_issues"]
    case "event":   return ["tickets_left", "price_min", "price_max"]
    case "job":     return ["applicants"]
    case "review":  return ["helpful_count"]
    default: return []
    }
}

private func prettyFieldName(_ raw: String) -> String {
    raw.replacingOccurrences(of: "_", with: " ").capitalized
}

private func relativeTime(_ raw: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let alt = ISO8601DateFormatter()
    alt.formatOptions = [.withInternetDateTime]
    let candidate = formatter.date(from: raw) ?? alt.date(from: raw)
    guard let date = candidate else {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let parsed = isoFormatter.date(from: raw) {
            return RelativeDateTimeFormatter().localizedString(for: parsed, relativeTo: Date())
        }
        return raw
    }
    let relative = RelativeDateTimeFormatter()
    relative.unitsStyle = .abbreviated
    return relative.localizedString(for: date, relativeTo: Date())
}

private func formatCount(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    if value == floor(value) { return String(Int(value)) }
    return String(format: "%.1f", value)
}

private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}
