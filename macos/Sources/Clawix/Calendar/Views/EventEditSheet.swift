import SwiftUI

struct EventEditSheet: View {
    @ObservedObject var manager: CalendarManager
    @State private var localDraft: CalendarEventDraft
    @State private var isSubmitting: Bool = false
    @State private var showCalendarPicker: Bool = false
    let mode: Mode

    enum Mode { case create, edit }

    init(manager: CalendarManager, draft: CalendarEventDraft, mode: Mode) {
        self.manager = manager
        self.mode = mode
        _localDraft = State(initialValue: draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    titleField
                    calendarPicker
                    Divider().opacity(0.35)
                    dateBlock
                    Divider().opacity(0.35)
                    locationRow
                    notesField
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .thinScrollers()
            Divider()
            footer
        }
        .frame(width: 440, height: 540)
        .background(Color(white: 0.135))
    }

    private var header: some View {
        HStack {
            Text(mode == .create ? "New event" : "Edit event")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CalendarTokens.Ink.primary)
            Spacer()
            Button { manager.cancelEdit() } label: {
                LucideIcon(.x, size: 14)
                    .foregroundColor(CalendarTokens.Ink.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var titleField: some View {
        TextField("Add a title", text: $localDraft.title)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(CalendarTokens.Ink.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CalendarTokens.Surface.window)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CalendarTokens.Divider.hairline, lineWidth: 1)
                    )
            )
    }

    private var calendarPicker: some View {
        let current = manager.source(forCalendarID: localDraft.calendarID)
        return HStack(spacing: 10) {
            Circle()
                .fill(current?.color ?? CalendarTokens.Ink.secondary)
                .frame(width: 12, height: 12)
            Text(current?.title ?? "Default")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CalendarTokens.Ink.primary)
            Spacer()
            Menu {
                ForEach(manager.sources.filter { !$0.isReadOnly }) { source in
                    Button(source.title) { localDraft.calendarID = source.id }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Change")
                        .font(.system(size: 12))
                        .foregroundColor(CalendarTokens.Ink.secondary)
                    LucideIcon(.chevronDown, size: 10)
                        .foregroundColor(CalendarTokens.Ink.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CalendarTokens.Surface.window)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CalendarTokens.Divider.hairline, lineWidth: 1)
                )
        )
    }

    private var dateBlock: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $localDraft.isAllDay) {
                Text("All day")
                    .font(.system(size: 13))
                    .foregroundColor(CalendarTokens.Ink.primary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack {
                Text("Starts")
                    .font(.system(size: 13))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .frame(width: 80, alignment: .leading)
                Spacer()
                if localDraft.isAllDay {
                    DatePicker("", selection: $localDraft.startDate, displayedComponents: [.date])
                        .labelsHidden()
                } else {
                    DatePicker("", selection: $localDraft.startDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
            HStack {
                Text("Ends")
                    .font(.system(size: 13))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .frame(width: 80, alignment: .leading)
                Spacer()
                if localDraft.isAllDay {
                    DatePicker("", selection: $localDraft.endDate, displayedComponents: [.date])
                        .labelsHidden()
                } else {
                    DatePicker("", selection: $localDraft.endDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
        }
    }

    private var locationRow: some View {
        HStack {
            LucideIcon(.link, size: 12)
                .foregroundColor(CalendarTokens.Ink.secondary)
                .frame(width: 18)
            TextField("Add location", text: Binding(
                get: { localDraft.location ?? "" },
                set: { localDraft.location = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(CalendarTokens.Ink.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CalendarTokens.Surface.window)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CalendarTokens.Divider.hairline, lineWidth: 1)
                )
        )
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LucideIcon(.fileText, size: 12)
                    .foregroundColor(CalendarTokens.Ink.secondary)
                Text("Notes")
                    .font(.system(size: 12))
                    .foregroundColor(CalendarTokens.Ink.secondary)
            }
            TextEditor(text: Binding(
                get: { localDraft.notes ?? "" },
                set: { localDraft.notes = $0.isEmpty ? nil : $0 }
            ))
            .font(.system(size: 13))
            .foregroundColor(CalendarTokens.Ink.primary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 80)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CalendarTokens.Surface.window)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CalendarTokens.Divider.hairline, lineWidth: 1)
                    )
            )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { manager.cancelEdit() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(CalendarTokens.Ink.primary)
                .padding(.horizontal, 14)
                .frame(height: 28)
            Button {
                guard !isSubmitting else { return }
                isSubmitting = true
                manager.editingDraft = localDraft
                Task {
                    await manager.commitDraft()
                    isSubmitting = false
                }
            } label: {
                Text(mode == .create ? "Create" : "Save")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CalendarTokens.Accent.todayFill)
                    )
            }
            .buttonStyle(.plain)
            .disabled(localDraft.title.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            .opacity(localDraft.title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
