import SwiftUI

struct CalendarScreen: View {

    @StateObject private var manager = CalendarManager()

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await manager.bootstrap()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Calendar")
                .font(BodyFont.system(size: CalendarTokens.Typography.headerSize, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, CalendarTokens.Spacing.screenPadding)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch manager.access {
        case .unknown, .requesting:
            CenteredMessage(title: "Loading calendar…", subtitle: nil)
        case .denied(let reason):
            CenteredMessage(title: "Calendar access denied", subtitle: reason)
        case .unavailable:
            CenteredMessage(title: "Calendar unavailable", subtitle: nil)
        case .granted:
            grantedContent
        }
    }

    private var grantedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(manager.events.count) events · \(manager.sources.count) calendars")
                .font(BodyFont.system(size: CalendarTokens.Typography.bodySize))
                .foregroundColor(Palette.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CalendarTokens.Spacing.screenPadding)
        .padding(.vertical, 12)
    }
}

private struct CenteredMessage: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(BodyFont.system(size: 14, wght: 500))
                .foregroundColor(Palette.textPrimary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
