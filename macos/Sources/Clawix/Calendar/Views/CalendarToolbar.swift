import SwiftUI

struct CalendarToolbar: View {
    @ObservedObject var manager: CalendarManager
    @FocusState private var searchFocused: Bool
    @State private var searchExpanded: Bool = false

    var body: some View {
        HStack(spacing: CalendarTokens.Spacing.toolbarButtonGap) {
            createButton
            searchField
            Spacer(minLength: 12)
            segmented
            Spacer(minLength: 12)
            navCluster
        }
        .padding(.leading, CalendarTokens.Spacing.toolbarLeading)
        .padding(.trailing, CalendarTokens.Spacing.toolbarTrailing)
        .frame(height: CalendarTokens.Geometry.toolbarHeight)
        .background(CalendarTokens.Surface.window)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CalendarTokens.Divider.hairline).frame(height: 1)
        }
    }

    private var createButton: some View {
        Button {
        } label: {
            LucideIcon(.plus, size: 13)
                .foregroundColor(CalendarTokens.Ink.primary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("New event")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            LucideIcon(.search, size: 11)
                .foregroundColor(CalendarTokens.Ink.secondary)
            TextField("Search", text: $manager.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: CalendarTokens.TypeSize.toolbar))
                .foregroundColor(CalendarTokens.Ink.primary)
                .focused($searchFocused)
            if !manager.searchQuery.isEmpty {
                Button {
                    manager.searchQuery = ""
                } label: {
                    LucideIcon(.circleX, size: 11)
                        .foregroundColor(CalendarTokens.Ink.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: searchExpanded ? 360 : 240, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(CalendarTokens.Surface.window)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(CalendarTokens.Divider.hairline, lineWidth: 1)
                )
        )
        .onChange(of: searchFocused) { _, focused in
            withAnimation(.easeOut(duration: 0.20)) {
                searchExpanded = focused
            }
        }
    }

    private var segmented: some View {
        SlidingSegmented(
            selection: Binding(
                get: { manager.viewMode },
                set: { manager.setViewMode($0) }
            ),
            options: CalendarViewMode.allCases.map { ($0, $0.localizedLabel) },
            height: 30,
            fontSize: 12
        )
        .frame(width: 248)
    }

    private var navCluster: some View {
        HStack(spacing: CalendarTokens.Spacing.toolbarButtonGap) {
            Button {
                withAnimation(CalendarTokens.Motion.pageStep) { manager.step(forward: false) }
            } label: {
                LucideIcon(.chevronLeft, size: 12)
                    .foregroundColor(CalendarTokens.Ink.primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(CalendarTokens.Motion.todayBump) { manager.goToToday() }
            } label: {
                Text("Today")
                    .font(.system(size: 12))
                    .foregroundColor(CalendarTokens.Ink.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: CalendarTokens.Radius.todayPill, style: .continuous)
                            .fill(CalendarTokens.Surface.window)
                            .overlay(
                                RoundedRectangle(cornerRadius: CalendarTokens.Radius.todayPill, style: .continuous)
                                    .stroke(CalendarTokens.Divider.hairline, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(CalendarTokens.Motion.pageStep) { manager.step(forward: true) }
            } label: {
                LucideIcon(.chevronRight, size: 12)
                    .foregroundColor(CalendarTokens.Ink.primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }
}
