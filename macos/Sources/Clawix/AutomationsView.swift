import SwiftUI

struct AutomationsView: View {

    private let sections: [AutomationTemplateSection] = [
        AutomationTemplateSection(
            title: "Status reports",
            cards: [
                AutomationTemplateCard(icon: "bubble.left.fill", color: Color(red: 0.55, green: 0.42, blue: 0.95), text: "Wrap up yesterday’s git activity into standup notes."),
                AutomationTemplateCard(icon: "doc.text.fill", color: Color(red: 0.62, green: 0.88, blue: 0.82), text: "Roll this week’s PRs, deploys, incidents and reviews into a digest."),
                AutomationTemplateCard(icon: "rectangle.fill", color: Color(white: 0.72), text: "Group last week’s PRs by teammate and topic; call out risks.")
            ],
            tallCards: false
        ),
        AutomationTemplateSection(
            title: "Release prep",
            cards: [
                AutomationTemplateCard(icon: "book.closed.fill", color: Color(red: 0.98, green: 0.55, blue: 0.42), text: "Write the weekly release notes from merged PRs, with links where available."),
                AutomationTemplateCard(icon: "checkmark.circle.fill", color: Color(red: 0.46, green: 0.82, blue: 0.42), text: "Before tagging, double-check the changelog, migrations, feature flags and tests."),
                AutomationTemplateCard(icon: "pencil", color: Color(red: 0.98, green: 0.72, blue: 0.30), text: "Refresh the changelog with this week’s highlights and the relevant PR links.")
            ],
            tallCards: true
        ),
        AutomationTemplateSection(
            title: "Incidents & triage",
            cards: [
                AutomationTemplateCard(icon: "globe.americas.fill", color: Color(red: 0.28, green: 0.74, blue: 0.64), text: "Round up CI failures and flaky tests from the last window and propose the top fixes."),
                AutomationTemplateCard(icon: "tray.fill", color: Color(white: 0.72), text: "Triage CI failures by grouping them by likely root cause, and propose a minimal fix per bucket."),
                AutomationTemplateCard(icon: "sparkle", color: Color(red: 0.34, green: 0.58, blue: 0.92), text: "Group recent errors into clusters by pattern and stage a follow-up summary.")
            ],
            tallCards: true
        )
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Automations")
                        .font(BodyFont.system(size: 20, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)

                    Text("Schedule recurring chats so routine work runs on its own.")
                        .foregroundColor(Palette.textSecondary)
                    .font(BodyFont.system(size: 12, wght: 500))
                }
                .padding(.bottom, 30)

                ForEach(sections) { section in
                    AutomationSectionView(section: section)
                        .padding(.bottom, 58)
                }
            }
            .frame(width: 744, alignment: .leading)
            .padding(.top, 73)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
            .offset(x: 8)
        }
        .thinScrollers()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

private struct AutomationTemplateSection: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let cards: [AutomationTemplateCard]
    let tallCards: Bool
}

private struct AutomationTemplateCard: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let text: LocalizedStringKey
}

private struct AutomationSectionView: View {
    let section: AutomationTemplateSection

    private let columns = [
        GridItem(.fixed(355), spacing: 16, alignment: .top),
        GridItem(.fixed(355), spacing: 16, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(section.title)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textSecondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(section.cards) { card in
                    AutomationCardView(card: card, tallCards: section.tallCards)
                }
            }
        }
    }

}

private struct AutomationCardView: View {
    let card: AutomationTemplateCard
    let tallCards: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LucideIcon.auto(card.icon, size: 14)
                .foregroundColor(card.color)
                .frame(width: 18, height: 18, alignment: .leading)

            Text(card.text)
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 355, alignment: .topLeading)
        .frame(minHeight: tallCards ? 116 : 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.145))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(white: 0.18), lineWidth: 0.5)
                )
        )
    }

}
