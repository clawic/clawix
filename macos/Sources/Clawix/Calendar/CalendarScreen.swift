import SwiftUI

struct CalendarScreen: View {

    @StateObject private var manager = CalendarManager()

    var body: some View {
        VStack(spacing: 0) {
            CalendarToolbar(manager: manager)
            mainLayout
        }
        .background(CalendarTokens.Surface.window)
        .task { await manager.bootstrap() }
        .sheet(isPresented: showSheetBinding) {
            if let draft = manager.editingDraft {
                EventEditSheet(manager: manager,
                                draft: draft,
                                mode: draft.id == nil ? .create : .edit)
            }
        }
    }

    private var mainLayout: some View {
        HStack(spacing: 0) {
            CalendarSubSidebar(manager: manager)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            inspectorIfNeeded
        }
        .animation(CalendarTokens.Motion.inspectorShow, value: manager.selectedEventID)
    }

    @ViewBuilder
    private var inspectorIfNeeded: some View {
        if manager.viewMode != .year,
           let selectedID = manager.selectedEventID,
           let event = manager.event(byID: selectedID) {
            EventInspectorPanel(manager: manager, event: event)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var showSheetBinding: Binding<Bool> {
        Binding(
            get: { manager.editingDraft != nil },
            set: { newValue in
                if !newValue { manager.cancelEdit() }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch manager.access {
        case .unknown, .requesting:
            centered("Loading calendar…")
        case .denied(let reason):
            centered("Calendar access denied", subtitle: reason)
        case .unavailable:
            centered("Calendar unavailable")
        case .granted:
            grantedContent
                .transition(.opacity)
                .id(manager.viewMode)
        }
    }

    @ViewBuilder
    private var grantedContent: some View {
        switch manager.viewMode {
        case .day:   DayView(manager: manager)
        case .week:  WeekView(manager: manager)
        case .month: MonthView(manager: manager)
        case .year:  YearView(manager: manager)
        }
    }

    private func centered(_ title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(CalendarTokens.Ink.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
