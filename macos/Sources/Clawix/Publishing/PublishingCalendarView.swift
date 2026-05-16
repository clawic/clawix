import SwiftUI

/// Month / week calendar of scheduled posts. Each cell shows a date label
/// and a stack of chip-style entries for the posts scheduled that day.
/// Clicking an empty cell opens the composer pre-filled with that day at
/// 09:00; clicking a chip opens a detail popover once post detail UI is
/// wired. The view polls `PublishingManager.refreshCalendar` every 30s while
/// visible; realtime WebSocket can replace it later without UI changes.
struct PublishingCalendarView: View {
    enum CalendarMode: String, CaseIterable { case month, week }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var manager: PublishingManager
    @AppStorage(ClawixPersistentSurfaceKeys.publishingCalendarMode) private var modeRaw: String = CalendarMode.month.rawValue
    @State private var anchorDate: Date = Date()
    @State private var pollerTask: Task<Void, Never>?

    private var mode: Binding<CalendarMode> {
        Binding(
            get: { CalendarMode(rawValue: modeRaw) ?? .month },
            set: { modeRaw = $0.rawValue }
        )
    }

    private var calendar: Calendar { Calendar.current }

    private var visibleRange: (start: Date, end: Date) {
        switch mode.wrappedValue {
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: anchorDate)
            let monthStart = calendar.date(from: comps) ?? anchorDate
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? anchorDate
            // Expand to the first weekday of the grid (week starts Monday).
            let weekday = calendar.component(.weekday, from: monthStart)
            // Calendar weekday: Sun=1, Mon=2, ... Sat=7. Convert to Mon-start.
            let leadingDays = (weekday + 5) % 7
            let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart
            return (gridStart, monthEnd)
        case .week:
            let weekday = calendar.component(.weekday, from: anchorDate)
            let leadingDays = (weekday + 5) % 7
            let weekStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -leadingDays, to: anchorDate) ?? anchorDate)
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            return (weekStart, weekEnd)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider().background(Color.white.opacity(0.06))
            switch manager.state {
            case .ready:
                grid
            case .bootstrapping, .idle:
                placeholder("Loading publishing calendar...")
            case .unavailable(let reason):
                placeholder(reason)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
        .onChange(of: anchorDate) { _, _ in Task { await reload() } }
        .onChange(of: modeRaw) { _, _ in Task { await reload() } }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            Button { shift(by: -1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            Button { anchorDate = Date() } label: {
                Text(verbatim: "Today")
                    .font(BodyFont.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .foregroundColor(Palette.textPrimary)

            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            Text(verbatim: monthTitle)
                .font(BodyFont.system(size: 14, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .padding(.leading, 6)

            Spacer(minLength: 12)

            SlidingSegmented(
                selection: mode,
                options: [
                    (CalendarMode.month, "Month"),
                    (CalendarMode.week, "Week"),
                ],
                height: 26,
                fontSize: 11
            )
            .frame(width: 150)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: anchorDate).capitalized
    }

    private func shift(by amount: Int) {
        let component: Calendar.Component = mode.wrappedValue == .month ? .month : .weekOfYear
        if let next = calendar.date(byAdding: component, value: amount, to: anchorDate) {
            anchorDate = next
        }
    }

    @ViewBuilder
    private var grid: some View {
        let range = visibleRange
        let dayCount = max(7, calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 7)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(weekdayHeaders, id: \.self) { day in
                    Text(verbatim: day)
                        .font(BodyFont.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                ForEach(Array(0..<dayCount), id: \.self) { offset in
                    let date = calendar.date(byAdding: .day, value: offset, to: range.start) ?? range.start
                    cell(for: date)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .thinScrollers()
    }

    private var weekdayHeaders: [String] {
        // Monday-start.
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }

    @ViewBuilder
    private func cell(for date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let isToday = calendar.isDate(date, inSameDayAs: Date())
        let postsForDay = posts(on: date)
        Button {
            openComposer(for: date)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(verbatim: String(day))
                        .font(BodyFont.system(size: 11.5, weight: .semibold))
                        .foregroundColor(isToday ? Palette.pastelBlue : Palette.textPrimary)
                    Spacer(minLength: 0)
                    if !postsForDay.isEmpty {
                        Text(verbatim: String(postsForDay.count))
                            .font(BodyFont.system(size: 10, weight: .semibold))
                            .foregroundColor(Palette.textSecondary)
                    }
                }
                ForEach(postsForDay.prefix(3)) { post in
                    postChip(post)
                }
                if postsForDay.count > 3 {
                    Text(verbatim: "+\(postsForDay.count - 3) more")
                        .font(BodyFont.system(size: 10, weight: .medium))
                        .foregroundColor(Palette.textTertiary)
                        .padding(.leading, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func postChip(_ post: ClawJSPublishingClient.Post) -> some View {
        let isPublished = post.publishStatus == "published"
        Text(verbatim: postLabel(post))
            .font(BodyFont.system(size: 10, weight: .medium))
            .foregroundColor(isPublished ? Color.green.opacity(0.85) : Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }

    private func postLabel(_ post: ClawJSPublishingClient.Post) -> String {
        if let scheduled = post.scheduledDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: scheduled)) - \(post.publishStatus)"
        }
        return post.publishStatus
    }

    private func posts(on date: Date) -> [ClawJSPublishingClient.Post] {
        manager.posts.filter { post in
            guard let scheduled = post.scheduledDate ?? post.publishedDate else { return false }
            return calendar.isDate(scheduled, inSameDayAs: date)
        }
    }

    private func openComposer(for date: Date) {
        let scheduledAt = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: date,
        ) ?? date
        appState.navigate(to: .publishingComposer(prefillBody: nil, prefillScheduleAt: scheduledAt))
    }

    private func reload() async {
        let range = visibleRange
        await manager.refreshCalendar(from: range.start, to: range.end)
    }

    private func startPolling() {
        stopPolling()
        Task { await reload() }
        pollerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await reload()
            }
        }
    }

    private func stopPolling() {
        pollerTask?.cancel()
        pollerTask = nil
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "megaphone")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Palette.textTertiary)
            Text(verbatim: message)
                .font(BodyFont.system(size: 12.5, weight: .medium))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if case .unavailable = manager.state {
                Button("Retry") {
                    Task { @MainActor in
                        await ClawJSServiceManager.shared.restart(.publishing)
                    }
                }
                .buttonStyle(.borderless)
                .font(BodyFont.system(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
