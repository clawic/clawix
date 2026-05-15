import SwiftUI

/// Full-bleed composer panel. Three sections (Accounts / Variants /
/// Schedule). Submits a single-variant `PostSpec` to publishing and navigates
/// back to `.publishingHome` on success. The `prefillBody` argument is set
/// when the user pushes an assistant message into the composer via
/// `AssistantMessageBubble`'s "Push to publishing" button; `prefillScheduleAt`
/// is set when the user opens the composer from a calendar date.
struct PublishingComposerView: View {
    enum ScheduleKind: String, CaseIterable { case now, datetime, draft }

    let prefillBody: String?
    let prefillScheduleAt: Date?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var manager: PublishingManager
    @State private var draft: String = ""
    @State private var selectedAccountIds: Set<String> = []
    @State private var scheduleKind: ScheduleKind = .datetime
    @State private var scheduleAt: Date = Date().addingTimeInterval(60 * 60)
    @State private var submitting = false
    @State private var errorMessage: String?

    private var authorizedAccounts: [ClawJSPublishingClient.ChannelAccount] {
        manager.channels.filter { $0.authorized }
    }

    private var familiesById: [String: ClawJSPublishingClient.Family] {
        Dictionary(uniqueKeysWithValues: manager.families.map { ($0.id, $0) })
    }

    private var maxChars: Int? {
        let selected = authorizedAccounts.filter { selectedAccountIds.contains($0.id) }
        let caps = selected.compactMap { familiesById[$0.familyId]?.capabilities.text.maxChars }
        return caps.min()
    }

    private var overLimit: Bool {
        guard let limit = maxChars else { return false }
        return draft.count > limit
    }

    private var bodyLength: Int { draft.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.06))
            ScrollView {
                VStack(spacing: 0) {
                    accountsSection
                    Divider().background(Color.white.opacity(0.06))
                    variantsSection
                    Divider().background(Color.white.opacity(0.06))
                    scheduleSection
                }
            }
            .thinScrollers()
            Divider().background(Color.white.opacity(0.06))
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .onAppear {
            if let prefillBody, !prefillBody.isEmpty, self.draft.isEmpty {
                self.draft = prefillBody
            }
            if let prefillScheduleAt {
                scheduleKind = .datetime
                scheduleAt = prefillScheduleAt
            }
            if manager.state == .idle { manager.bootstrap() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                appState.navigate(to: .publishingHome)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text(verbatim: "Back").font(BodyFont.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .foregroundColor(Palette.textPrimary)
            }
            .buttonStyle(.plain)

            Text(verbatim: "New post")
                .font(BodyFont.system(size: 18, weight: .semibold))
                .foregroundColor(Palette.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var accountsSection: some View {
        sectionLabel("Accounts")
        if authorizedAccounts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "No connected accounts yet.")
                    .font(BodyFont.system(size: 12.5, weight: .medium))
                    .foregroundColor(Palette.textSecondary)
                Button {
                    appState.navigate(to: .publishingChannels)
                } label: {
                    Text(verbatim: "Connect a channel")
                        .font(BodyFont.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                        .foregroundColor(Palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(authorizedAccounts) { account in
                        accountChip(account)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private func accountChip(_ account: ClawJSPublishingClient.ChannelAccount) -> some View {
        let selected = selectedAccountIds.contains(account.id)
        Button {
            if selected { selectedAccountIds.remove(account.id) }
            else { selectedAccountIds.insert(account.id) }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(selected ? Color.green : Color.white.opacity(0.16))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: account.displayName)
                        .font(BodyFont.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                    if let handle = account.handle, !handle.isEmpty {
                        Text(verbatim: "@\(handle)")
                            .font(BodyFont.system(size: 10.5, weight: .medium))
                            .foregroundColor(Palette.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var variantsSection: some View {
        sectionLabel("Content")
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $draft)
                .font(BodyFont.system(size: 13.5, weight: .regular))
                .foregroundColor(Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                )
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(verbatim: charCountLabel)
                    .font(BodyFont.system(size: 10.5, weight: .medium))
                    .foregroundColor(overLimit ? Color.red.opacity(0.85) : Palette.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var charCountLabel: String {
        if let max = maxChars {
            return "\(bodyLength) / \(max)"
        }
        return "\(bodyLength)"
    }

    @ViewBuilder
    private var scheduleSection: some View {
        sectionLabel("Schedule")
        VStack(alignment: .leading, spacing: 12) {
            SlidingSegmented(
                selection: $scheduleKind,
                options: [
                    (ScheduleKind.now, "Publish now"),
                    (ScheduleKind.datetime, "Pick time"),
                    (ScheduleKind.draft, "Save draft"),
                ],
                height: 30,
                fontSize: 11.5
            )
            .frame(width: 340)

            if scheduleKind == .datetime {
                DatePicker(
                    "",
                    selection: $scheduleAt,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .colorScheme(.dark)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(BodyFont.system(size: 11, weight: .semibold))
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(BodyFont.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color.red.opacity(0.85))
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Button {
                submit()
            } label: {
                Text(verbatim: submitLabel)
                    .font(BodyFont.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(canSubmit ? Color.white.opacity(0.92) : Color.white.opacity(0.18))
                    )
                    .foregroundColor(canSubmit ? Color.black : Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var submitLabel: String {
        if submitting { return "Submitting..." }
        switch scheduleKind {
        case .now: return "Publish now"
        case .datetime: return "Schedule"
        case .draft: return "Save draft"
        }
    }

    private var canSubmit: Bool {
        if submitting { return false }
        if scheduleKind != .draft && selectedAccountIds.isEmpty { return false }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if overLimit { return false }
        return true
    }

    private func submit() {
        let accountIds = Array(selectedAccountIds)
        let trimmedBody = draft
        let kind = scheduleKind
        let scheduledDate = scheduleAt
        submitting = true
        errorMessage = nil
        Task { @MainActor in
            defer { submitting = false }
            let schedule: ClawJSPublishingClient.PostSpec.Schedule
            let editorial: String
            switch kind {
            case .now:
                schedule = .now()
                editorial = "ready"
            case .datetime:
                schedule = .datetime(ClawJSPublishingClient.iso8601(scheduledDate))
                editorial = "ready"
            case .draft:
                schedule = .unscheduled
                editorial = "drafting"
            }
            let spec = ClawJSPublishingClient.PostSpec(
                accounts: accountIds,
                editorialStatus: editorial,
                schedule: schedule,
                variants: [
                    .init(
                        isOriginal: true,
                        channelAccountId: nil,
                        blocks: [.init(body: trimmedBody)]
                    )
                ]
            )
            do {
                _ = try await manager.createPost(spec: spec)
                appState.navigate(to: .publishingHome)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
