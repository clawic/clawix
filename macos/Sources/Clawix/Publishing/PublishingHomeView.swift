import SwiftUI

/// Landing for the Publishing sidebar entry. Hosts a sliding segmented control
/// (Calendar / Channels) and delegates the body to the active tab. The
/// composer is reached from Calendar's "+ New post" button or by clicking
/// a day cell; it lives on its own route (`.publishingComposer`), not as a tab.
struct PublishingHomeView: View {
    enum HomeTab: String, CaseIterable { case calendar, channels }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var manager: PublishingManager
    @AppStorage(ClawixPersistentSurfaceKeys.publishingHomeTab) private var tabRaw: String = HomeTab.calendar.rawValue

    private var tab: Binding<HomeTab> {
        Binding(
            get: { HomeTab(rawValue: tabRaw) ?? .calendar },
            set: { tabRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(Color.white.opacity(0.06))
            Group {
                switch tab.wrappedValue {
                case .calendar: PublishingCalendarView()
                case .channels: PublishingChannelsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background)
        .onAppear {
            if manager.state == .idle { manager.bootstrap() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(verbatim: "Publishing")
                .font(BodyFont.system(size: 18, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            SlidingSegmented(
                selection: tab,
                options: [
                    (HomeTab.calendar, "Calendar"),
                    (HomeTab.channels, "Channels"),
                ],
                height: 28,
                fontSize: 11.5
            )
            .frame(width: 220)
            if tab.wrappedValue == .calendar {
                Button {
                    appState.navigate(to: .publishingComposer(prefillBody: nil))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text(verbatim: "New post")
                            .font(BodyFont.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                    )
                    .foregroundColor(Palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
