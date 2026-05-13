import SwiftUI

struct PlaceholderPage: View {
    let category: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: category.title)

            SettingsCard {
                HStack(spacing: 12) {
                    LucideIcon.auto(category.iconName, size: 11)
                        .foregroundColor(Palette.textSecondary)
                    Text("Coming soon")
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 22)
            }
        }
    }
}

enum UsageDisplayMode: String, CaseIterable {
    case used
    case remaining
}

struct UsagePage: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("clawix.settings.usage.displayMode") private var displayMode: UsageDisplayMode = .used

    /// Per-bucket entries other than the base "codex" id (which mirrors
    /// the general snapshot we already render at the top). Sorted by
    /// limit name so the order is stable across renders.
    private var perModelBuckets: [(id: String, snapshot: RateLimitSnapshot)] {
        appState.rateLimitsByLimitId
            .filter { $0.key != "codex" }
            .sorted { ($0.value.limitName ?? $0.key) < ($1.value.limitName ?? $1.key) }
            .map { ($0.key, $0.value) }
    }

    private var hasAnyBars: Bool {
        let general = appState.rateLimits.map { $0.primary != nil || $0.secondary != nil } ?? false
        return general || !perModelBuckets.isEmpty
    }

    private var usageOptions: [(UsageDisplayMode, String)] {
        [(.used, "Used"), (.remaining, "Remaining")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Usage")

            if let snapshot = appState.rateLimits, snapshot.primary != nil || snapshot.secondary != nil {
                HStack(alignment: .center) {
                    Text("General usage limits")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.leading, 3)
                    Spacer()
                    if hasAnyBars {
                        SlidingSegmented(selection: $displayMode, options: usageOptions)
                            .frame(width: 190)
                    }
                }
                .padding(.bottom, 14)

                SettingsCard {
                    UsageBarStack(snapshot: snapshot, mode: displayMode)
                }
            }

            ForEach(perModelBuckets, id: \.id) { entry in
                Text(verbatim: SettingsLimitsFormatter.perModelSectionTitle(name: entry.snapshot.limitName ?? entry.id))
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.leading, 3)
                    .padding(.bottom, 14)
                    .padding(.top, 28)
                SettingsCard {
                    UsageBarStack(snapshot: entry.snapshot, mode: displayMode)
                }
            }

            if let credits = appState.rateLimits?.credits {
                SectionLabel(title: "Credit")
                SettingsCard {
                    CreditRow(title: SettingsLimitsFormatter.creditTitle(for: credits),
                              detail: "Use credit to send messages when you hit your usage limits.")
                }
            }

            if !hasAnyBars && appState.rateLimits?.credits == nil {
                SettingsCard {
                    HStack(alignment: .center, spacing: 12) {
                        UsageIcon(size: 15, lineWidth: 1.7)
                            .foregroundColor(Palette.textSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: "No usage data yet")
                                .font(BodyFont.system(size: 13, wght: 600))
                                .foregroundColor(Palette.textPrimary)
                            Text(verbatim: "Usage limits appear here after the runtime reports a rate-limit snapshot.")
                                .font(BodyFont.system(size: 11.5, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                        }
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                .padding(.top, 14)
            }
        }
    }
}

struct UsageBarStack: View {
    let snapshot: RateLimitSnapshot
    let mode: UsageDisplayMode

    private var windows: [RateLimitWindow] {
        [snapshot.primary, snapshot.secondary].compactMap { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(windows.enumerated()), id: \.offset) { entry in
                if entry.offset > 0 {
                    CardDivider()
                }
                UsageBarRow(
                    title: SettingsLimitsFormatter.detailedWindowLabel(for: entry.element),
                    detail: SettingsLimitsFormatter.detailedResetLabel(for: entry.element),
                    percent: entry.element.usedPercent,
                    mode: mode
                )
            }
        }
    }
}

struct UsageBarRow: View {
    let title: String
    let detail: String
    let percent: Int
    let mode: UsageDisplayMode

    private var displayPercent: Int {
        switch mode {
        case .used: return percent
        case .remaining: return max(0, 100 - percent)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: detail)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 90, height: 7)
                    if displayPercent > 0 {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(Color.white.opacity(0.95))
                            .frame(width: max(7, 90 * CGFloat(displayPercent) / 100), height: 7)
                    }
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: "\(displayPercent) %")
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(.white)
                    Text(mode == .used ? "used" : "remaining")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

struct CreditRow: View {
    let title: String
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
